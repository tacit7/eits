<script>
  import { formatTime, formatDateRelative } from '../../utils/datetime.js'
  import { autoScroll } from '../../actions/autoScroll.js'

  export let activeChannelId = null
  export let messages = []
  export let activeAgents = []
  export let channelMembers = []
  export let workingAgents = {}
  export let slashItems = []
  export let live

  let inputValue = ''
  let inputElement

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
      shouldAutoScroll = true
    }
  }

</script>

<style>
  :global(div[id^="AgentMessagesPanel"]) {
    height: 100%;
  }
</style>

<div class="flex flex-col h-full">
  <!-- Messages Container -->
  <div
    use:autoScroll={{ trigger: messages?.length }}
    class="flex-1 overflow-y-auto px-4 py-2"
    style="scrollbar-width: none; -ms-overflow-style: none;"
  >
    {#if messages && messages.length > 0}
      <div class="space-y-0">
        {#each messages as message, idx}
          <!-- Date separator -->
          {#if idx === 0 || formatDateRelative(messages[idx - 1].inserted_at) !== formatDateRelative(message.inserted_at)}
            <div class="flex items-center gap-3 my-4">
              <div class="flex-1 h-px bg-base-content/5"></div>
              <span class="text-xs uppercase tracking-wider font-medium text-base-content/25 whitespace-nowrap">{formatDateRelative(message.inserted_at)}</span>
              <div class="flex-1 h-px bg-base-content/5"></div>
            </div>
          {/if}

          <!-- Message -->
          <div
            class="group py-3 px-2 -mx-2 rounded-lg transition-colors {message.sender_role === 'system' ? '' : message.sender_role === 'agent' ? 'bg-primary/[0.03]' : 'hover:bg-base-content/[0.02]'}"
          >
            {#if message.sender_role === 'system'}
              <!-- System message -->
              <div class="flex items-center gap-2 text-xs text-base-content/30 italic px-1">
                <span class="w-1 h-1 rounded-full bg-base-content/20 flex-shrink-0"></span>
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
              <div class="flex items-start gap-2.5">
                <!-- Sender icon -->
                {#if message.sender_role === 'user'}
                  <div class="w-4 h-4 rounded-full mt-1 flex-shrink-0 bg-success/20 flex items-center justify-center">
                    <div class="w-1.5 h-1.5 rounded-full bg-success"></div>
                  </div>
                {:else}
                  <img src={getProviderIcon(message)} class="w-4 h-4 mt-1 flex-shrink-0" alt={message.provider || 'Agent'} />
                {/if}

                <div class="min-w-0 flex-1">
                  <div class="flex items-baseline gap-2 flex-wrap">
                    <span class="text-[13px] font-semibold {message.sender_role === 'user' ? 'text-base-content/70' : 'text-primary/80'}">
                      {message.sender_role === 'user' ? 'You' : (message.provider || 'Agent')}
                    </span>

                    {#if message.sender_role === 'agent' && message.session_id}
                      {@const agent = activeAgents.find(a => a.id === message.session_id)}
                      <button
                        class="font-mono text-[11px] px-1.5 py-0.5 rounded bg-base-content/[0.05] text-base-content/35 hover:text-primary hover:bg-primary/5 transition-colors cursor-pointer"
                        on:click={() => navigateToDm(message.session_id)}
                        title="Session #{message.session_id}"
                      >
                        {truncate(agent?.name || message.session_name) || `@${message.session_id}`}
                      </button>
                    {/if}

                    {#if message.number}
                      <span class="font-mono text-xs text-base-content/20">#{message.number}</span>
                    {/if}
                    <span class="text-[11px] text-base-content/25">{formatTime(message.inserted_at)}</span>
                    <button
                      class="opacity-0 group-hover:opacity-100 ml-auto text-base-content/20 hover:text-error transition-all cursor-pointer"
                      on:click={() => live.pushEvent('delete_message', { id: String(message.id) })}
                      title="Delete message"
                    >
                      <svg class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
                    </button>
                  </div>

                  <p class="mt-1 text-sm leading-relaxed text-base-content/85 whitespace-pre-wrap break-words">{message.body}</p>

                  <!-- Usage metadata for agent messages -->
                  {#if message.sender_role === 'agent' && message.metadata && message.metadata.total_cost_usd}
                    <div class="mt-2 flex flex-wrap gap-1.5">
                      {#if message.metadata.total_cost_usd}
                        <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40">
                          ${message.metadata.total_cost_usd.toFixed(4)}
                        </span>
                      {/if}
                      {#if message.metadata.usage?.input_tokens}
                        <span class="inline-flex items-center px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40">
                          {message.metadata.usage.input_tokens} in
                        </span>
                      {/if}
                      {#if message.metadata.usage?.output_tokens}
                        <span class="inline-flex items-center px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40">
                          {message.metadata.usage.output_tokens} out
                        </span>
                      {/if}
                      {#if message.metadata.duration_ms}
                        <span class="inline-flex items-center px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40">
                          {(message.metadata.duration_ms / 1000).toFixed(1)}s
                        </span>
                      {/if}
                      {#if message.metadata.num_turns}
                        <span class="inline-flex items-center px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40">
                          {message.metadata.num_turns} turns
                        </span>
                      {/if}
                    </div>
                  {/if}
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
        <p class="text-sm font-semibold text-base-content/60">No messages yet</p>
        <p class="mt-1 text-xs text-base-content/30">Messages from agents will appear here</p>
      </div>
    {/if}
  </div>

  <!-- Typing indicator -->
  {#if workingMembers.length > 0}
    <div class="flex-shrink-0 px-4 py-1">
      <div class="flex items-center gap-2 text-xs text-base-content/40">
        <span class="inline-flex gap-[3px]">
          <span class="w-1.5 h-1.5 rounded-full bg-base-content/30 animate-bounce" style="animation-delay: 0ms"></span>
          <span class="w-1.5 h-1.5 rounded-full bg-base-content/30 animate-bounce" style="animation-delay: 150ms"></span>
          <span class="w-1.5 h-1.5 rounded-full bg-base-content/30 animate-bounce" style="animation-delay: 300ms"></span>
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
      class="relative bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl border border-base-content/5 shadow-sm p-4 flex flex-col"
    >
      <div class="flex gap-2">
        <div class="relative flex-1">
          <input
            type="text"
            bind:value={inputValue}
            bind:this={inputElement}
            on:input={handleInputChange}
            on:keydown={handleInputKeydown}
            placeholder="Message agents... @id to mention, /skill for commands"
            class="input input-sm w-full bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-sm h-10"
            autocomplete="off"
          />

          <!-- @ Autocomplete Dropdown -->
          {#if showAutocomplete && autocompleteOptions.length > 0}
            <div class="absolute bottom-full left-0 right-0 mb-1.5 bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] border border-base-content/8 rounded-xl shadow-lg max-h-56 overflow-y-auto z-50 p-1">
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
          class="btn btn-sm btn-primary min-h-0 h-10 px-5"
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
</div>
