<script>
  import { formatTime, formatDateRelative } from '../../utils/datetime.js'
  import { autoScroll } from '../../actions/autoScroll.js'
  import { marked } from 'marked'
  import DOMPurify from 'dompurify'
  import ThreadPanel from '../ThreadPanel.svelte'

  // Configure marked once at module level
  marked.setOptions({ gfm: true, breaks: true })

  export let activeChannelId = null
  export let messages = []
  export let hasMoreMessages = false
  export let activeAgents = []
  export let channelMembers = []
  export let workingAgents = {}
  export let slashItems = []
  export let activeThread = null
  export let live

  let loadingOlder = false
  let openOverflowId = null
  let inspectMessage = null

  function loadOlderMessages() {
    if (!messages.length || loadingOlder) return
    loadingOlder = true
    live.pushEvent('load_older_messages', { before_id: String(messages[0].id) }, () => {
      loadingOlder = false
    })
  }

  let inputValue = ''
  let inputElement

  // Scroll / jump-to-bottom
  let messagesContainer
  let isAtBottom = true

  function handleScrollState() {
    if (!messagesContainer) return
    isAtBottom = messagesContainer.scrollHeight - messagesContainer.scrollTop <= messagesContainer.clientHeight + 120
  }

  function jumpToBottom() {
    if (!messagesContainer) return
    messagesContainer.scrollTop = messagesContainer.scrollHeight
    isAtBottom = true
  }

  // Search
  let showSearch = false
  let searchQuery = ''
  let searchInput

  $: filteredMessages = searchQuery.trim()
    ? messages.filter(m => (m.body || '').toLowerCase().includes(searchQuery.toLowerCase()))
    : messages

  function openSearch() {
    showSearch = true
    setTimeout(() => searchInput?.focus(), 0)
  }

  function closeSearch() {
    showSearch = false
    searchQuery = ''
  }

  function handleDocKeydown(e) {
    if ((e.metaKey || e.ctrlKey) && e.key === 'f' && document.activeElement !== inputElement) {
      e.preventDefault()
      openSearch()
    }
    if (e.key === 'Escape' && showSearch) {
      closeSearch()
    }
    if (e.key === 'Escape' && openOverflowId !== null) {
      openOverflowId = null
    }
    if (e.key === 'Escape' && inspectMessage !== null) {
      inspectMessage = null
    }
  }

  // @ mention autocomplete state
  let showAutocomplete = false
  let autocompleteOptions = []
  let selectedAutocompleteIndex = 0

  // / slash command autocomplete state
  let showSlashAutocomplete = false
  let slashOptions = []
  let selectedSlashIndex = 0
  let slashTriggerPos = -1

  // Reactive: channel members currently working
  $: workingMembers = channelMembers
    .filter(m => workingAgents && workingAgents[m.session_id])
    .map(m => {
      const agent = activeAgents.find(a => a.id === m.session_id)
      return {
        id: m.session_id,
        name: m.session_name || agent?.name || agent?.agent_description || `@${m.session_id}`
      }
    })

  // Message history for up/down navigation
  let messageHistory = []
  let historyIndex = -1
  let currentDraft = ''

  const typeBadges = {
    skill:   { label: 'skill',  cls: 'bg-primary/10 text-primary' },
    command: { label: 'cmd',    cls: 'bg-secondary/10 text-secondary' },
    agent:   { label: 'agent',  cls: 'bg-accent/10 text-accent' },
    prompt:  { label: 'prompt', cls: 'bg-warning/10 text-warning' },
  }
  const typeOrder = ['skill', 'command', 'agent', 'prompt']

  function groupSlashItems(items) {
    const groups = {}
    for (const item of items) {
      const t = item.type || 'other'
      if (!groups[t]) groups[t] = []
      groups[t].push(item)
    }
    const ordered = []
    const allTypes = [...typeOrder, ...Object.keys(groups).filter(t => !typeOrder.includes(t))]
    for (const type of allTypes) {
      if (!groups[type]) continue
      ordered.push({ header: true, type })
      for (const item of groups[type]) {
        ordered.push({ header: false, ...item })
      }
    }
    return ordered
  }

  function getProviderIcon(message) {
    if (message.sender_role === 'user') return null
    const p = (message.provider || '').toLowerCase()
    if (p === 'openai') return '/images/openai.svg'
    if (p === 'codex') return '/images/codex.svg'
    return '/images/claude.svg'
  }

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;')
  }

  // Renders message body with @mention tokens highlighted.
  // @all and @<integer> are wrapped in a styled span.
  function renderBody(body) {
    if (!body) return ''
    const escaped = escapeHtml(body)
    return escaped.replace(/@(all|\d+)/g, (match, token) => {
      const label = token === 'all' ? '@all' : `@${token}`
      return `<span class="inline-flex items-center px-1 py-0.5 rounded text-xs font-mono font-semibold bg-primary/10 text-primary">${label}</span>`
    })
  }

  // Renders agent message body as parsed markdown with @mention highlighting.
  // Sanitized via DOMPurify before injection. @mentions applied after sanitization
  // since they are numeric IDs or "all" — no XSS surface.
  const DOMPURIFY_CONFIG = {
    ALLOWED_TAGS: ['p', 'strong', 'em', 'b', 'i', 'code', 'pre', 'ul', 'ol', 'li',
                   'br', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'a',
                   'span', 'hr', 'del', 's'],
    ALLOWED_ATTR: ['class', 'href', 'target', 'rel']
  }

  function renderMarkdownBody(body) {
    if (!body) return ''
    const html = marked.parse(body)
    const clean = DOMPurify.sanitize(html, DOMPURIFY_CONFIG)
    return clean.replace(/@(all|\d+)/g, (match, token) => {
      const label = token === 'all' ? '@all' : `@${token}`
      return `<span class="inline-flex items-center px-1 py-0.5 rounded text-xs font-mono font-semibold bg-primary/10 text-primary">${label}</span>`
    })
  }

  function truncate(str, max = 10) {
    if (!str) return str
    return str.length > max ? str.slice(0, max) + '…' : str
  }

  function navigateToDm(sessionId) {
    window.location.href = `/dm/${sessionId}`
  }

  function checkSlashTrigger(value, cursorPos) {
    // Find last '/' before cursor that's at start or after space/newline
    for (let i = cursorPos - 1; i >= 0; i--) {
      if (value[i] === '/') {
        const before = i === 0 ? '' : value[i - 1]
        if (i === 0 || before === ' ' || before === '\n') {
          return i
        }
        return -1
      }
      if (value[i] === ' ' || value[i] === '\n') return -1
    }
    return -1
  }

  function handleInputChange(e) {
    const value = e.target.value
    const cursorPos = e.target.selectionStart

    // Check / slash trigger first
    const triggerPos = checkSlashTrigger(value, cursorPos)
    if (triggerPos !== -1) {
      const query = value.slice(triggerPos + 1, cursorPos).toLowerCase()
      const filtered = slashItems.filter(item =>
        item.slug.toLowerCase().includes(query) ||
        (item.description || '').toLowerCase().includes(query) ||
        (item.type || '').toLowerCase().includes(query)
      )
      if (filtered.length > 0) {
        slashTriggerPos = triggerPos
        slashOptions = filtered
        selectedSlashIndex = 0
        showSlashAutocomplete = true
        showAutocomplete = false
        return
      }
    }
    showSlashAutocomplete = false

    // Find @ mentions that are being typed
    const textBeforeCursor = value.substring(0, cursorPos)
    const lastAtIndex = textBeforeCursor.lastIndexOf('@')

    if (lastAtIndex !== -1) {
      const textAfterAt = textBeforeCursor.substring(lastAtIndex + 1)

      // Check if we're still typing the mention (no space after @)
      if (!textAfterAt.includes(' ')) {
        const searchTerm = textAfterAt.toLowerCase()

        // Use channel members for @ autocomplete, fall back to activeAgents for display info
        const memberOptions = channelMembers.map(m => {
          const agent = activeAgents.find(a => a.id === m.session_id)
          return {
            id: m.session_id,
            name: m.session_name || agent?.name || agent?.agent_description || `Session ${m.session_id}`,
            provider: agent?.provider || 'claude',
            model: agent?.model,
            description: agent?.agent_description
          }
        })

        const filtered = memberOptions
          .filter(a =>
            String(a.id).includes(searchTerm) ||
            (a.name && a.name.toLowerCase().includes(searchTerm)) ||
            (a.description && a.description.toLowerCase().includes(searchTerm)) ||
            (a.provider && a.provider.toLowerCase().includes(searchTerm))
          )

        // Prepend @all option
        const allOption = { id: 'all', name: 'All Channel Members', provider: 'system', model: null, description: 'Require all channel members to respond' }

        if (filtered.length > 0 || searchTerm === '') {
          const agentOptions = searchTerm === '' ? memberOptions : filtered
          const showAll = searchTerm === '' || 'all'.includes(searchTerm)
          autocompleteOptions = showAll ? [allOption, ...agentOptions] : agentOptions
          selectedAutocompleteIndex = 0
          showAutocomplete = true
          return
        }
      }
    }

    showAutocomplete = false
  }

  function handleInputKeydown(e) {
    // Handle slash autocomplete navigation
    if (showSlashAutocomplete) {
      const selectableItems = slashOptions.length
      if (e.key === 'ArrowDown') {
        e.preventDefault()
        selectedSlashIndex = (selectedSlashIndex + 1) % selectableItems
        return
      } else if (e.key === 'ArrowUp') {
        e.preventDefault()
        selectedSlashIndex = selectedSlashIndex === 0 ? selectableItems - 1 : selectedSlashIndex - 1
        return
      } else if (e.key === 'Tab' || e.key === 'Enter') {
        e.preventDefault()
        selectSlashItem(slashOptions[selectedSlashIndex])
        return
      } else if (e.key === 'Escape') {
        showSlashAutocomplete = false
        return
      }
    }

    // Handle @ autocomplete navigation if autocomplete is shown
    if (showAutocomplete) {
      if (e.key === 'ArrowDown') {
        e.preventDefault()
        selectedAutocompleteIndex = (selectedAutocompleteIndex + 1) % autocompleteOptions.length
        return
      } else if (e.key === 'ArrowUp') {
        e.preventDefault()
        selectedAutocompleteIndex = selectedAutocompleteIndex === 0
          ? autocompleteOptions.length - 1
          : selectedAutocompleteIndex - 1
        return
      } else if (e.key === 'Tab' || e.key === 'Enter') {
        if (autocompleteOptions.length > 0) {
          e.preventDefault()
          selectAutocomplete(autocompleteOptions[selectedAutocompleteIndex].id)
        }
        return
      } else if (e.key === 'Escape') {
        showAutocomplete = false
        return
      }
    }

    // Handle message history navigation
    if (e.key === 'ArrowUp' || (e.ctrlKey && e.key === 'p')) {
      e.preventDefault()
      if (messageHistory.length === 0) return

      if (historyIndex === -1) {
        currentDraft = inputValue
      }

      if (historyIndex < messageHistory.length - 1) {
        historyIndex++
        inputValue = messageHistory[historyIndex]
      }
    } else if (e.key === 'ArrowDown' || (e.ctrlKey && e.key === 'n')) {
      e.preventDefault()
      if (historyIndex === -1) return

      historyIndex--
      if (historyIndex === -1) {
        inputValue = currentDraft
        currentDraft = ''
      } else {
        inputValue = messageHistory[historyIndex]
      }
    }

    // Enter = send; Shift+Enter = newline (textarea default)
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSubmit()
    }
  }

  function selectAutocomplete(sessionId) {
    const cursorPos = inputElement.selectionStart
    const textBeforeCursor = inputValue.substring(0, cursorPos)
    const textAfterCursor = inputValue.substring(cursorPos)
    const lastAtIndex = textBeforeCursor.lastIndexOf('@')

    const mentionText = sessionId === 'all' ? 'all' : String(sessionId)
    inputValue = textBeforeCursor.substring(0, lastAtIndex) + `@${mentionText} ` + textAfterCursor
    showAutocomplete = false

    setTimeout(() => {
      const newPos = lastAtIndex + mentionText.length + 2
      inputElement.setSelectionRange(newPos, newPos)
      inputElement.focus()
    }, 0)
  }

  function selectSlashItem(item) {
    if (!item) return
    const cursorPos = inputElement.selectionStart
    const prefix = inputValue.slice(0, slashTriggerPos)
    const suffix = inputValue.slice(cursorPos)
    const insertion = item.type === 'agent' ? `@${item.slug} ` : `/${item.slug} `

    inputValue = prefix + insertion + suffix
    showSlashAutocomplete = false

    setTimeout(() => {
      const newPos = prefix.length + insertion.length
      inputElement.setSelectionRange(newPos, newPos)
      inputElement.focus()
    }, 0)
  }

  function autoResizeTextarea(el) {
    el.style.height = 'auto'
    el.style.height = Math.min(el.scrollHeight, 120) + 'px'
  }

  function handleSubmit(e) {
    const body = inputValue.trim()

    if (body) {
      live.pushEvent('send_channel_message', {
        channel_id: activeChannelId,
        body: body
      })

      messageHistory.unshift(body)
      if (messageHistory.length > 50) {
        messageHistory = messageHistory.slice(0, 50)
      }

      historyIndex = -1
      currentDraft = ''
      inputValue = ''
      if (inputElement) inputElement.style.height = 'auto'
    }
  }

</script>

<style>
  :global(div[id^="AgentMessagesPanel"]) {
    height: 100%;
  }

  /* Markdown-rendered agent message body */
  :global(.message-body p) {
    margin-bottom: 0.4em;
  }
  :global(.message-body p:last-child) {
    margin-bottom: 0;
  }
  :global(.message-body ol) {
    list-style-type: decimal;
    padding-left: 1.4em;
    margin: 0.3em 0 0.5em;
  }
  :global(.message-body ul) {
    list-style-type: disc;
    padding-left: 1.4em;
    margin: 0.3em 0 0.5em;
  }
  :global(.message-body li) {
    line-height: 1.55;
    margin-bottom: 0.2em;
  }
  :global(.message-body li:last-child) {
    margin-bottom: 0;
  }
  :global(.message-body li > ol),
  :global(.message-body li > ul) {
    margin: 0.15em 0 0.15em;
  }
  :global(.message-body code:not(pre code)) {
    font-family: ui-monospace, 'Cascadia Code', 'SF Mono', monospace;
    font-size: 0.8em;
    padding: 0.1em 0.35em;
    border-radius: 3px;
    background-color: rgb(127 127 127 / 0.1);
  }
  :global(.message-body pre) {
    font-family: ui-monospace, 'Cascadia Code', 'SF Mono', monospace;
    font-size: 0.8em;
    line-height: 1.5;
    padding: 0.65em 0.9em;
    border-radius: 6px;
    background-color: rgb(127 127 127 / 0.07);
    overflow-x: auto;
    margin: 0.4em 0;
  }
  :global(.message-body pre code) {
    background: none;
    padding: 0;
    font-size: 1em;
  }
  :global(.message-body strong, .message-body b) {
    font-weight: 600;
  }
  :global(.message-body em, .message-body i) {
    font-style: italic;
  }
  :global(.message-body del, .message-body s) {
    text-decoration: line-through;
    opacity: 0.6;
  }
  :global(.message-body h1) { font-size: 1.1em; font-weight: 600; margin: 0.5em 0 0.25em; line-height: 1.3; }
  :global(.message-body h2) { font-size: 1.05em; font-weight: 600; margin: 0.5em 0 0.25em; line-height: 1.3; }
  :global(.message-body h3) { font-size: 1em; font-weight: 600; margin: 0.4em 0 0.2em; }
  :global(.message-body h4, .message-body h5, .message-body h6) { font-weight: 600; margin: 0.3em 0 0.15em; }
  :global(.message-body blockquote) {
    border-left: 2px solid rgb(127 127 127 / 0.25);
    padding-left: 0.75em;
    margin: 0.4em 0;
    opacity: 0.75;
  }
  :global(.message-body a) {
    text-decoration: underline;
    text-underline-offset: 2px;
    opacity: 0.85;
  }
  :global(.message-body hr) {
    border: none;
    border-top: 1px solid rgb(127 127 127 / 0.15);
    margin: 0.75em 0;
  }
</style>

<svelte:document on:keydown={handleDocKeydown} on:click={() => openOverflowId = null} />

<div class="flex h-full min-w-0">
  <!-- Main chat column -->
  <div class="relative flex flex-col flex-1 min-w-0">
  <!-- Search bar -->
  {#if showSearch}
    <div class="flex-shrink-0 px-4 py-2 border-b border-base-content/5 bg-base-100">
      <div class="flex items-center gap-2">
        <div class="relative flex-1">
          <svg class="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-base-content/30 pointer-events-none" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M9 3.5a5.5 5.5 0 1 0 0 11 5.5 5.5 0 0 0 0-11ZM2 9a7 7 0 1 1 12.452 4.391l3.328 3.329a.75.75 0 1 1-1.06 1.06l-3.329-3.328A7 7 0 0 1 2 9Z" clip-rule="evenodd" /></svg>
          <input
            bind:this={searchInput}
            bind:value={searchQuery}
            type="text"
            placeholder="Search messages..."
            class="w-full input input-xs bg-base-200/50 border-base-content/8 pl-8 pr-4 text-base placeholder:text-base-content/25 focus:border-primary/30"
            autocomplete="off"
          />
        </div>
        {#if searchQuery}
          <span class="text-[11px] text-base-content/30 whitespace-nowrap">{filteredMessages.length} result{filteredMessages.length !== 1 ? 's' : ''}</span>
        {/if}
        <button on:click={closeSearch} class="text-base-content/30 hover:text-base-content/60 transition-colors flex-shrink-0" title="Close (Esc)">
          <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor"><path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z" /></svg>
        </button>
      </div>
    </div>
  {/if}

  <!-- Messages Container -->
  <div
    bind:this={messagesContainer}
    on:scroll={handleScrollState}
    use:autoScroll={{ trigger: filteredMessages?.length }}
    class="flex-1 overflow-y-auto px-4 py-2"
    style="scrollbar-width: none; -ms-overflow-style: none;"
  >
    {#if hasMoreMessages && !searchQuery}
      <div class="flex justify-center py-3">
        <button
          on:click={loadOlderMessages}
          disabled={loadingOlder}
          class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {#if loadingOlder}
            <span class="w-3 h-3 rounded-full border border-base-content/30 border-t-transparent animate-spin"></span>
            Loading…
          {:else}
            <svg class="w-3 h-3" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M10 17a.75.75 0 0 1-.75-.75V5.612L5.29 9.77a.75.75 0 0 1-1.08-1.04l5.25-5.5a.75.75 0 0 1 1.08 0l5.25 5.5a.75.75 0 1 1-1.08 1.04l-3.96-4.158V16.25A.75.75 0 0 1 10 17Z" clip-rule="evenodd"/></svg>
            Load older messages
          {/if}
        </button>
      </div>
    {/if}

    {#if filteredMessages && filteredMessages.length > 0}
      <div class="space-y-0">
        {#each filteredMessages as message, idx}
          <!-- Date separator -->
          {#if idx === 0 || formatDateRelative(filteredMessages[idx - 1].inserted_at) !== formatDateRelative(message.inserted_at)}
            <div class="flex items-center gap-3 my-4">
              <div class="flex-1 h-px bg-base-content/5"></div>
              <span class="text-xs uppercase tracking-wider font-medium text-base-content/25 whitespace-nowrap">{formatDateRelative(message.inserted_at)}</span>
              <div class="flex-1 h-px bg-base-content/5"></div>
            </div>
          {/if}

          <!-- Message -->
          {@const prevMessage = idx > 0 ? filteredMessages[idx - 1] : null}
          {@const isTurnBoundary = prevMessage && prevMessage.sender_role !== message.sender_role && message.sender_role !== 'system' && prevMessage.sender_role !== 'system'}
          <div
            class="group relative px-2 -mx-2 rounded-lg transition-colors {isTurnBoundary ? 'mt-4' : ''} {message.sender_role === 'system' ? 'py-1' : message.sender_role === 'agent' ? 'py-4 border-l-2 border-primary/30 hover:bg-base-content/[0.04] hover:border-primary/50' : 'py-4 hover:bg-base-content/[0.04]'}"
          >
            {#if message.sender_role === 'system'}
              <!-- System message -->
              <div class="flex items-center gap-2 text-[11px] text-base-content/25 italic pl-3 border-l-2 border-base-content/[0.08]">
                <span class="flex-1">{message.body}</span>
                <button
                  class="opacity-0 group-hover:opacity-100 text-base-content/20 hover:text-error transition-all cursor-pointer"
                  on:click={() => live.pushEvent('delete_message', { id: String(message.id) })}
                  title="Delete message"
                >
                  <svg class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
                </button>
              </div>
            {:else}
              <!-- Hover actions: absolute overlay, not in flex flow -->
              <div class="absolute top-2 right-1 opacity-0 group-hover:opacity-100 flex items-center gap-0.5 transition-opacity z-10">
                <!-- Reply in thread -->
                <button
                  class="p-1 rounded text-base-content/30 hover:text-primary/70 hover:bg-base-content/[0.06] transition-colors cursor-pointer"
                  on:click={() => live.pushEvent('open_thread', { message_id: String(message.id) })}
                  title="Reply in thread"
                >
                  <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M2 5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H6l-4 4V5Z" clip-rule="evenodd"/></svg>
                </button>
                <!-- Copy -->
                <button
                  class="p-1 rounded text-base-content/30 hover:text-base-content/70 hover:bg-base-content/[0.06] transition-colors cursor-pointer"
                  on:click={() => navigator.clipboard.writeText(message.body || '')}
                  title="Copy message"
                >
                  <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>
                </button>
                <!-- Overflow (contains destructive actions) -->
                <div class="relative">
                  <button
                    class="p-1 rounded text-base-content/25 hover:text-base-content/60 hover:bg-base-content/[0.06] transition-colors cursor-pointer"
                    on:click|stopPropagation={() => openOverflowId = openOverflowId === message.id ? null : message.id}
                    title="More actions"
                  >
                    <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor"><path d="M10 6a2 2 0 1 1 0-4 2 2 0 0 1 0 4ZM10 12a2 2 0 1 1 0-4 2 2 0 0 1 0 4ZM10 18a2 2 0 1 1 0-4 2 2 0 0 1 0 4Z"/></svg>
                  </button>
                  {#if openOverflowId === message.id}
                    <div class="absolute right-0 top-full mt-0.5 bg-base-100 border border-base-content/10 rounded-lg shadow-lg py-0.5 w-32 z-20">
                      <button
                        type="button"
                        class="w-full flex items-center gap-2 px-3 py-1.5 text-[13px] text-base-content/60 hover:bg-base-content/[0.06] hover:text-base-content transition-colors cursor-pointer"
                        on:click|stopPropagation={() => { inspectMessage = message; openOverflowId = null }}
                      >
                        Inspect
                      </button>
                      <div class="my-0.5 border-t border-base-content/5"></div>
                      <button
                        class="w-full flex items-center gap-2 px-3 py-1.5 text-[13px] text-error/80 hover:bg-error/[0.08] hover:text-error transition-colors cursor-pointer"
                        on:click|stopPropagation={() => { live.pushEvent('delete_message', { id: String(message.id) }); openOverflowId = null }}
                      >
                        <svg class="w-3.5 h-3.5 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
                        Delete
                      </button>
                    </div>
                  {/if}
                </div>
              </div>

              <div class="flex items-start gap-2.5">
                <!-- Sender icon -->
                {#if message.sender_role === 'user'}
                  <div class="w-4 h-4 mt-1 flex-shrink-0 text-base-content/40">
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
                      <path d="M10 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM3.465 14.493a1.23 1.23 0 0 0 .41 1.412A9.957 9.957 0 0 0 10 18c2.31 0 4.438-.784 6.131-2.1.43-.333.604-.903.408-1.41a7.002 7.002 0 0 0-13.074.003Z" />
                    </svg>
                  </div>
                {:else}
                  <img src={getProviderIcon(message)} class="w-4 h-4 mt-1 flex-shrink-0" alt={message.provider || 'Agent'} />
                {/if}

                <div class="min-w-0 flex-1">
                  <!-- Identity line: no flex-wrap; hover actions removed from this flow -->
                  <div class="flex items-baseline gap-2">
                    {#if message.sender_role === 'user'}
                      <span class="text-[13px] font-semibold text-base-content/70">You</span>
                    {:else if message.session_id}
                      {@const agent = activeAgents.find(a => a.id === message.session_id)}
                      <button
                        class="text-[13px] font-semibold text-primary/80 hover:text-primary transition-colors cursor-pointer"
                        on:click={() => navigateToDm(message.session_id)}
                        title="Open DM with this agent"
                      >
                        {agent?.name || message.session_name || `@${message.session_id}`}
                      </button>
                    {:else}
                      <span class="text-[13px] font-semibold text-primary/80">{message.provider || 'Agent'}</span>
                    {/if}

                    <span class="text-[11px] text-base-content/25">{formatTime(message.inserted_at)}</span>

                    {#if message.number}
                      <span class="font-mono text-[11px] text-base-content/[0.15] opacity-0 group-hover:opacity-100 transition-opacity">#{message.number}</span>
                    {/if}
                  </div>

                  <div class="max-w-[720px]">
                    <div class="message-body mt-1 text-sm leading-relaxed text-base-content/85 break-words">
                      {#if message.sender_role === 'agent'}
                        {@html renderMarkdownBody(message.body)}
                      {:else}
                        <p class="whitespace-pre-wrap">{@html renderBody(message.body)}</p>
                      {/if}
                    </div>

                    <!-- Usage metadata for agent messages -->
                    {#if message.sender_role === 'agent' && message.metadata && message.metadata.total_cost_usd}
                      <div class="mt-2 flex flex-nowrap gap-x-1.5 min-w-0 overflow-hidden">
                        {#if message.metadata.total_cost_usd}
                          <span title="Total cost" class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-primary/50">
                            ${message.metadata.total_cost_usd.toFixed(4)}
                          </span>
                        {/if}
                        {#if message.metadata.usage?.input_tokens}
                          <span title="Input tokens" class="inline-flex items-center px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/35">
                            {message.metadata.usage.input_tokens} in
                          </span>
                        {/if}
                        {#if message.metadata.usage?.output_tokens}
                          <span title="Output tokens" class="inline-flex items-center px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/35">
                            {message.metadata.usage.output_tokens} out
                          </span>
                        {/if}
                        {#if message.metadata.duration_ms}
                          <span title="Duration" class="inline-flex items-center px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/35">
                            {(message.metadata.duration_ms / 1000).toFixed(1)}s
                          </span>
                        {/if}
                        {#if message.metadata.num_turns}
                          <span title="Number of turns" class="inline-flex items-center px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/25">
                            {message.metadata.num_turns} turns
                          </span>
                        {/if}
                      </div>
                    {/if}

                    <!-- Reactions -->
                    {#if message.reactions && message.reactions.length > 0}
                      <div class="mt-2 flex flex-wrap gap-1">
                        {#each message.reactions as reaction}
                          <button
                            class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-full text-[12px] bg-base-content/[0.05] hover:bg-primary/10 hover:text-primary transition-colors"
                            on:click={() => live.pushEvent('toggle_reaction', { message_id: String(message.id), emoji: reaction.emoji })}
                            title="React with {reaction.emoji}"
                          >
                            {reaction.emoji}
                            <span class="text-base-content/50 text-[11px] tabular-nums">{reaction.count}</span>
                          </button>
                        {/each}
                      </div>
                    {/if}

                    <!-- Thread reply count -->
                    {#if message.thread_reply_count > 0}
                      <button
                        class="mt-2 flex items-center gap-1.5 text-[11px] text-primary/60 hover:text-primary transition-colors"
                        on:click={() => live.pushEvent('open_thread', { message_id: String(message.id) })}
                      >
                        <svg class="w-3 h-3" viewBox="0 0 20 20" fill="currentColor">
                          <path fill-rule="evenodd" d="M2 5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H6l-4 4V5Z" clip-rule="evenodd"/>
                        </svg>
                        {message.thread_reply_count} {message.thread_reply_count === 1 ? 'reply' : 'replies'}
                      </button>
                    {/if}
                  </div>
                </div>
              </div>
            {/if}
          </div>
        {/each}
      </div>
    {:else}
      <div class="flex flex-col items-center justify-center h-full text-center py-16">
        <div class="w-16 h-16 rounded-2xl bg-base-content/[0.03] border border-base-content/5 flex items-center justify-center mb-4">
          <svg class="w-7 h-7 text-base-content/15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
          </svg>
        </div>
        {#if searchQuery}
          <p class="text-sm font-semibold text-base-content/60">No results for "{searchQuery}"</p>
          <p class="mt-1 text-xs text-base-content/30">Try a different search term</p>
        {:else}
          <p class="text-sm font-semibold text-base-content/60">No messages yet</p>
          <p class="mt-1 text-xs text-base-content/30">Messages from agents will appear here</p>
        {/if}
      </div>
    {/if}
  </div>

  <!-- Jump to bottom -->
  {#if !isAtBottom}
    <button
      on:click={jumpToBottom}
      class="absolute bottom-28 right-4 z-10 w-8 h-8 rounded-full bg-base-200 border border-base-content/10 shadow-md flex items-center justify-center text-base-content/50 hover:text-base-content hover:bg-base-300 transition-all"
      title="Jump to bottom"
      aria-label="Jump to bottom"
    >
      <svg class="w-4 h-4" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M10 3a.75.75 0 0 1 .75.75v10.638l3.96-4.158a.75.75 0 1 1 1.08 1.04l-5.25 5.5a.75.75 0 0 1-1.08 0l-5.25-5.5a.75.75 0 1 1 1.08-1.04l3.96 4.158V3.75A.75.75 0 0 1 10 3Z" clip-rule="evenodd" /></svg>
    </button>
  {/if}

  <!-- Typing indicator -->
  {#if workingMembers.length > 0}
    <div class="flex-shrink-0 px-4 py-1">
      <div class="flex items-center gap-2 text-xs text-base-content/40">
        <span class="inline-flex gap-[3px]">
          <span class="inline-block w-2 h-2 rounded-full bg-success animate-pulse flex-shrink-0"></span>
        </span>
        <span>
          {#if workingMembers.length === 1}
            <span class="font-medium text-base-content/50">{workingMembers[0].name}</span> is working
          {:else if workingMembers.length === 2}
            <span class="font-medium text-base-content/50">{workingMembers[0].name}</span> and <span class="font-medium text-base-content/50">{workingMembers[1].name}</span> are working
          {:else}
            <span class="font-medium text-base-content/50">{workingMembers[0].name}</span> and {workingMembers.length - 1} others are working
          {/if}
        </span>
      </div>
    </div>
  {/if}

  <!-- Composer (matches DM page card style) -->
  <div class="flex-shrink-0 pt-2">
    <form
      on:submit|preventDefault={handleSubmit}
      class="relative bg-base-200 rounded-xl border border-base-content/5 shadow-sm p-4 flex flex-col"
    >
      <div class="flex gap-2">
        <div class="relative flex-1">
          <textarea
            bind:value={inputValue}
            bind:this={inputElement}
            on:input={e => { handleInputChange(e); autoResizeTextarea(e.target) }}
            on:keydown={handleInputKeydown}
            placeholder="Message agents... @id to mention, /skill for commands"
            class="textarea textarea-bordered w-full text-sm rounded-lg bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors resize-none overflow-y-auto text-base-content"
            rows="1"
            style="max-height: 7.5rem; line-height: 1.5rem;"
            autocomplete="off"
          ></textarea>

          <!-- @ Autocomplete Dropdown -->
          {#if showAutocomplete && autocompleteOptions.length > 0}
            <div class="absolute bottom-full left-0 right-0 mb-1.5 bg-base-100 border border-base-content/8 rounded-xl shadow-lg max-h-56 overflow-y-auto z-50 p-1">
              {#each autocompleteOptions as option, idx}
                <button
                  type="button"
                  class="w-full flex items-center gap-2.5 px-3 py-2 rounded-lg text-left transition-colors {idx === selectedAutocompleteIndex ? 'bg-base-content/[0.06]' : 'hover:bg-base-content/[0.04]'}"
                  on:click={() => selectAutocomplete(option.id)}
                  on:mouseenter={() => selectedAutocompleteIndex = idx}
                >
                  <span class="font-mono text-[13px] font-semibold text-base-content/80">@{option.id}</span>
                  <span class="text-[13px] text-base-content/50 flex-1 truncate">{option.name}</span>
                  <span class="font-mono text-[11px] text-base-content/30">{option.provider}{option.model ? ` / ${option.model}` : ''}</span>
                </button>
              {/each}
            </div>
          {/if}

          <!-- / Slash Command Autocomplete Dropdown -->
          {#if showSlashAutocomplete && slashOptions.length > 0}
            <div class="absolute bottom-full left-0 right-0 mb-1.5 bg-base-100 border border-base-content/10 rounded-xl shadow-xl max-h-[280px] overflow-y-auto z-50">
              {#each groupSlashItems(slashOptions) as entry, idx}
                {#if entry.header}
                  <div class="px-3 py-1 text-xs font-semibold uppercase tracking-wider text-base-content/40 bg-base-content/[0.02] sticky top-0">
                    {{ skill: 'Skills', command: 'Commands', agent: 'Agents', prompt: 'Prompts' }[entry.type] || entry.type}
                  </div>
                {:else}
                  {@const flatIdx = slashOptions.indexOf(entry)}
                  <button
                    type="button"
                    class="w-full flex items-start gap-3 px-3 py-2 text-left transition-colors text-sm {flatIdx === selectedSlashIndex ? 'bg-base-content/[0.06]' : 'hover:bg-base-content/[0.04]'}"
                    on:click={() => selectSlashItem(entry)}
                    on:mouseenter={() => { selectedSlashIndex = flatIdx }}
                  >
                    {#if typeBadges[entry.type]}
                      <span class="shrink-0 mt-0.5 inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium {typeBadges[entry.type].cls}">
                        {typeBadges[entry.type].label}
                      </span>
                    {/if}
                    <span class="min-w-0 flex-1">
                      <span class="flex items-center gap-2">
                        <span class="font-medium text-base-content">{entry.type === 'agent' ? '@' : '/'}{entry.slug}</span>
                      </span>
                      {#if entry.description}
                        <span class="text-xs text-base-content/50 truncate block">{entry.description}</span>
                      {/if}
                    </span>
                  </button>
                {/if}
              {/each}
            </div>
          {/if}
        </div>

        <button
          type="submit"
          class="btn btn-sm btn-primary min-h-0 h-11 px-5"
          disabled={!inputValue || inputValue.trim() === ''}
          aria-label="Send message"
        >
          <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <line x1="22" y1="2" x2="11" y2="13"/>
            <polygon points="22 2 15 22 11 13 2 9 22 2"/>
          </svg>
        </button>
      </div>
    </form>
  </div>
  </div><!-- end main chat column -->

  <!-- Thread panel (slides in when a thread is open) -->
  {#if activeThread}
    <ThreadPanel thread={activeThread} {live} />
  {/if}

  {#if inspectMessage}
    <div class="modal modal-open z-50">
      <div class="modal-box max-w-2xl">
        <div class="flex items-center justify-between mb-3">
          <h3 class="font-bold text-sm">Message #{inspectMessage.id}</h3>
          <button class="btn btn-xs btn-ghost" on:click={() => inspectMessage = null}>Close</button>
        </div>
        <pre class="text-xs bg-base-200 rounded-lg p-3 overflow-auto max-h-96 whitespace-pre-wrap break-all">{JSON.stringify(inspectMessage, null, 2)}</pre>
      </div>
      <div class="modal-backdrop" on:click={() => inspectMessage = null}></div>
    </div>
  {/if}
</div>
