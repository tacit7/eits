<script>
  import { onMount } from 'svelte'
  import ChannelsSidebar from '../ChannelsSidebar.svelte'
  import { formatTime, formatDateRelative } from '../../utils/datetime.js'
  import { autoScroll } from '../../actions/autoScroll.js'

  // Heroicons
  import ChatBubbleLeftSvg from 'heroicons/24/outline/chat-bubble-left.svg'

  export let channels = []
  export let activeChannelId = null
  export let messages = []
  export let unreadCounts = {}
  export let agentStatusCounts = {}
  export let prompts = []
  export let activeAgents = []
  export let workingAgents = {}
  export let live

  // Debug working agents
  $: if (workingAgents) {
    console.log('🔍 workingAgents updated:', workingAgents)
    console.log('🔍 workingAgents keys:', Object.keys(workingAgents))
  }
  let inputValue = ''
  let inputElement

  // Autocomplete state
  let showAutocomplete = false
  let autocompleteOptions = []
  let selectedAutocompleteIndex = 0

  // Message history for up/down navigation
  let messageHistory = []
  let historyIndex = -1
  let currentDraft = ''

  function openAgentDrawer() {
    live.pushEvent('toggle_agent_drawer', {})
  }

  function handleSessionIdClick(sessionId) {
    console.log('🔍 Badge clicked, session_id:', sessionId)
    // Navigate to DM page for this session
    window.location.href = `/dm/${sessionId}`
  }

  function handleInputChange(e) {
    const value = e.target.value
    const cursorPos = e.target.selectionStart

    // Find @ mentions that are being typed
    const textBeforeCursor = value.substring(0, cursorPos)
    const lastAtIndex = textBeforeCursor.lastIndexOf('@')

    if (lastAtIndex !== -1) {
      const textAfterAt = textBeforeCursor.substring(lastAtIndex + 1)

      // Check if we're still typing the mention (no space after @)
      if (!textAfterAt.includes(' ')) {
        // Use activeAgents prop (queried from DB) for autocomplete
        const searchTerm = textAfterAt.toLowerCase()

        const filtered = activeAgents
          .map(a => ({
            id: a.id,
            name: a.name || a.agent_description || `Session ${a.id}`,
            provider: a.provider || 'claude',
            model: a.model,
            description: a.agent_description
          }))
          .filter(a =>
            String(a.id).includes(searchTerm) ||
            (a.name && a.name.toLowerCase().includes(searchTerm)) ||
            (a.description && a.description.toLowerCase().includes(searchTerm)) ||
            (a.provider && a.provider.toLowerCase().includes(searchTerm))
          )

        if (filtered.length > 0 || searchTerm === '') {
          autocompleteOptions = searchTerm === '' ? activeAgents.map(a => ({
            id: a.id,
            name: a.name || a.agent_description || `Session ${a.id}`,
            provider: a.provider || 'claude',
            model: a.model,
            description: a.agent_description
          })) : filtered
          selectedAutocompleteIndex = 0
          showAutocomplete = true
          return
        }
      }
    }

    showAutocomplete = false
  }

  function handleInputKeydown(e) {
    // Handle autocomplete navigation if autocomplete is shown
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

    // Handle message history navigation (up/down arrows or Ctrl+P/N when autocomplete is NOT shown)
    if (e.key === 'ArrowUp' || (e.ctrlKey && e.key === 'p')) {
      e.preventDefault()
      if (messageHistory.length === 0) return

      // Save current draft when starting to navigate history
      if (historyIndex === -1) {
        currentDraft = inputValue
      }

      // Move up in history (towards older messages)
      if (historyIndex < messageHistory.length - 1) {
        historyIndex++
        inputValue = messageHistory[historyIndex]
      }
    } else if (e.key === 'ArrowDown' || (e.ctrlKey && e.key === 'n')) {
      e.preventDefault()
      if (historyIndex === -1) return

      // Move down in history (towards newer messages)
      historyIndex--
      if (historyIndex === -1) {
        // Back to current draft
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

    const idStr = String(sessionId)
    inputValue = textBeforeCursor.substring(0, lastAtIndex) + `@${idStr} ` + textAfterCursor
    showAutocomplete = false

    setTimeout(() => {
      const newPos = lastAtIndex + idStr.length + 2
      inputElement.setSelectionRange(newPos, newPos)
      inputElement.focus()
    }, 0)
  }

  function handleSubmit(e) {
    const body = inputValue.trim()

    if (body) {
      // Match @<integer> mentions
      const mentionRegex = /@(\d+)/g
      const mentions = []
      let match

      while ((match = mentionRegex.exec(body)) !== null) {
        const id = parseInt(match[1], 10)
        if (!isNaN(id) && !mentions.includes(id)) {
          mentions.push(id)
        }
      }

      if (mentions.length > 0) {
        mentions.forEach(sessionId => {
          live.pushEvent('send_direct_message', {
            session_id: sessionId,
            body: body,
            channel_id: activeChannelId
          })
        })
      } else {
        live.pushEvent('send_channel_message', {
          channel_id: activeChannelId,
          body: body
        })
      }

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
  /* Theme colors */
  :global(:root) {
    --bg-shell: #f8f8f8;
    --bg-surface: #ffffff;
    --bg-sidebar: #111827;
    --text-primary: #1d1c1d;
    --text-secondary: #616061;
    --text-tertiary: #9ca3af;
    --border-subtle: #dddddd;
    --accent-primary: #0f766e;
    --accent-soft: #e0f2f1;
  }

  :global([data-theme="dark"]) {
    --bg-shell: #1a1d21;
    --bg-surface: #222529;
    --bg-sidebar: #1a1d21;
    --text-primary: #f8f8f8;
    --text-secondary: #dcddde;
    --text-tertiary: #9ca3af;
    --border-subtle: #2f3437;
    --accent-primary: #14b8a6;
    --accent-soft: #064e3b;
  }

  .agent-messages-container {
    display: flex;
    height: 100vh;
    background-color: var(--bg-shell);
  }

  .main-content {
    flex: 1;
    display: flex;
    flex-direction: column;
  }

  .channel-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1rem 1.5rem;
    border-bottom: 1px solid var(--border-subtle);
    background-color: var(--bg-surface);
  }

  .channel-title {
    font-size: 1.125rem;
    font-weight: 700;
    color: var(--text-primary);
  }

  .header-right {
    display: flex;
    align-items: center;
    gap: 1rem;
  }

  .agent-status {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    font-size: 0.875rem;
  }

  .new-agent-btn {
    padding: 0.5rem 1rem;
    background-color: var(--accent-primary);
    color: white;
    border: none;
    border-radius: 0.375rem;
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    transition: opacity 0.15s;
    white-space: nowrap;
  }

  .new-agent-btn:hover {
    opacity: 0.9;
  }

  .status-badge {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
    padding: 0.25rem 0.75rem;
    border-radius: 0.375rem;
    font-weight: 600;
  }

  .status-badge.status-active {
    background-color: #d1fae5;
    color: #065f46;
  }

  :global(.dark) .status-badge.status-active {
    background-color: #064e3b;
    color: #6ee7b7;
  }

  .status-badge.status-idle {
    background-color: #dbeafe;
    color: #1e40af;
  }

  :global(.dark) .status-badge.status-idle {
    background-color: #1e3a8a;
    color: #93c5fd;
  }

  .status-badge.status-working {
    background-color: #fed7aa;
    color: #92400e;
  }

  :global(.dark) .status-badge.status-working {
    background-color: #78350f;
    color: #fcd34d;
  }

  .status-badge.status-nats {
    background-color: #e0e7ff;
    color: #3730a3;
  }

  :global(.dark) .status-badge.status-nats {
    background-color: #312e81;
    color: #a5b4fc;
  }

  .status-separator {
    color: var(--text-tertiary);
  }

  .messages-scroll {
    flex: 1;
    overflow-y: auto;
    padding: 1rem 1.5rem;
  }

  /* Date separator */
  .date-separator {
    display: flex;
    align-items: center;
    justify-content: center;
    margin: 1.5rem 0;
  }

  .date-badge {
    font-size: 0.75rem;
    font-weight: 600;
    padding: 0.25rem 0.75rem;
  }

  .session-id-badge {
    font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace;
    cursor: pointer;
    transition: all 0.15s;
    position: relative;
    z-index: 10;
    pointer-events: auto;
  }

  .session-id-badge:hover {
    transform: scale(1.05);
    background-color: var(--accent-soft);
  }

  .input-area {
    border-top: 1px solid var(--border-subtle);
    background-color: var(--bg-surface);
    padding: 1rem 1.5rem;
  }

  .input-form {
    display: flex;
    align-items: flex-end;
    gap: 0.5rem;
  }

  .message-input {
    flex: 1;
    padding: 0.75rem 1rem;
    border-radius: 0.375rem;
    background-color: var(--bg-surface);
    border: 1px solid var(--border-subtle);
    font-size: 0.9375rem;
    color: var(--text-primary);
  }

  .message-input:focus {
    outline: 2px solid var(--accent-primary);
    outline-offset: 0;
    border-color: transparent;
  }

  .send-button {
    padding: 0.75rem 1.5rem;
    border-radius: 0.375rem;
    background-color: var(--accent-primary);
    border: none;
    color: white;
    font-weight: 600;
    cursor: pointer;
    transition: background-color 0.15s, opacity 0.15s;
  }

  .send-button:hover:not(:disabled) {
    opacity: 0.9;
  }

  .send-button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  /* Autocomplete Dropdown */
  .autocomplete-dropdown {
    position: absolute;
    bottom: 100%;
    left: 0;
    right: 4.5rem;
    margin-bottom: 0.5rem;
    background-color: var(--bg-surface);
    border: 1px solid var(--border-subtle);
    border-radius: 0.375rem;
    box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
    max-height: 200px;
    overflow-y: auto;
    z-index: 50;
  }

  .autocomplete-item {
    width: 100%;
    padding: 0.5rem 1rem;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    background: none;
    border: none;
    text-align: left;
    cursor: pointer;
    transition: background-color 0.15s;
    color: var(--text-primary);
  }

  .autocomplete-item:hover,
  .autocomplete-item.selected {
    background-color: var(--bg-shell);
  }

  .autocomplete-id {
    font-family: 'SF Mono', 'Monaco', 'Consolas', monospace;
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--text-primary);
  }

  .autocomplete-name {
    font-size: 0.875rem;
    color: var(--text-secondary);
    margin-left: 0.5rem;
  }

  .autocomplete-provider {
    font-size: 0.75rem;
    color: var(--text-tertiary);
    margin-left: auto;
  }

  .empty-state {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100%;
  }

  .empty-state-content {
    text-align: center;
  }

  .empty-icon {
    width: 5rem;
    height: 5rem;
    margin: 0 auto 1rem;
    border-radius: 50%;
    background-color: #e5e7eb;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  :global(.dark) .empty-icon {
    background-color: #374151;
  }
</style>

<div class="agent-messages-container">
  <!-- Channels Sidebar -->
  <ChannelsSidebar
    {channels}
    {activeChannelId}
    {unreadCounts}
    {live}
  />

  <!-- Main Content -->
  <div class="main-content">
    <!-- Channel Header -->
    <div class="channel-header">
      <div class="channel-title">
        {#if activeChannelId}
          {channels.find(c => c.id === activeChannelId)?.name || 'Project'}
        {:else}
          Select a project
        {/if}
      </div>
      <div class="header-right">
        <div class="agent-status">
          <span class="status-badge status-active">
            {agentStatusCounts.active || 0} active
          </span>
          <span class="status-badge status-idle">
            {agentStatusCounts.idle || 0} idle
          </span>
          <span class="status-badge status-working">
            {agentStatusCounts.working || 0} running
          </span>
          <span class="status-separator">·</span>
          <span class="status-badge status-nats">
            NATS: Live
          </span>
        </div>
        <button class="new-agent-btn" on:click={openAgentDrawer}>
          + New Agent
        </button>
      </div>
    </div>

    <!-- Messages Container -->
    <div
      use:autoScroll={{ trigger: messages?.length }}
      class="messages-scroll"
    >
      <!-- Working Agents Indicator -->
      {#if workingAgents && Object.keys(workingAgents).length > 0}
        <div class="alert alert-info mb-3">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6 animate-pulse"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>
          <span>
            {#each Object.entries(workingAgents) as [sessionId, isWorking]}
              {#if isWorking}
                {@const agent = activeAgents.find(a => a.id == sessionId)}
                {#if agent}
                  Agent @{sessionId} ({agent.name || agent.description || 'unknown'}) is working...
                {:else}
                  Agent @{sessionId} is working...
                {/if}
              {/if}
            {/each}
          </span>
        </div>
      {/if}

      {#if messages && messages.length > 0}
        {#each messages as message, idx}
          <!-- Date separator -->
          {#if idx === 0 || formatDateRelative(messages[idx - 1].inserted_at) !== formatDateRelative(message.inserted_at)}
            <div class="date-separator">
              <div class="badge badge-ghost badge-sm date-badge">
                {formatDateRelative(message.inserted_at)}
              </div>
            </div>
          {/if}

          <!-- Message bubble (DM-style) -->
          <div class="group hover:bg-base-300/30 px-2 py-1.5 -mx-2 rounded mb-1">
            <div class="flex gap-3">
              <div class="flex-shrink-0">
                <div class="w-10 h-10 rounded-full bg-primary/20 flex items-center justify-center text-primary font-bold text-sm">
                  {message.sender_role === 'user' ? 'U' : (message.provider ? message.provider.charAt(0).toUpperCase() : 'A')}
                </div>
              </div>
              <div class="flex-1 min-w-0">
                <div class="flex items-baseline gap-2">
                  <span class={"font-semibold text-sm " + (message.sender_role === 'user' ? 'text-primary' : 'text-accent')}>
                    {message.sender_role === 'user' ? 'You' : (message.provider || 'Agent')}
                  </span>
                  <time class="text-xs text-base-content/40">{formatTime(message.inserted_at)}</time>
                  {#if message.sender_role === 'agent' && message.session_id}
                    <span
                      class="text-xs text-base-content/50 font-mono cursor-pointer hover:text-primary transition-colors"
                      on:click={() => handleSessionIdClick(message.session_id)}
                      on:keydown={(e) => e.key === 'Enter' && handleSessionIdClick(message.session_id)}
                      role="button"
                      tabindex="0"
                    >
                      @{message.session_id}
                    </span>
                  {/if}
                  {#if message.sender_role === 'agent' && message.session_id}
                    {@const agent = activeAgents.find(a => a.id === message.session_id)}
                    <span
                      class="badge badge-xs badge-outline session-id-badge ml-auto"
                      on:click={() => handleSessionIdClick(message.session_id)}
                      on:keydown={(e) => e.key === 'Enter' && handleSessionIdClick(message.session_id)}
                      role="button"
                      tabindex="0"
                      title={agent ? `Session #${message.session_id}` : String(message.session_id)}
                    >
                      {agent?.name || message.session_name || `#${message.session_id}`}
                    </span>
                  {/if}
                </div>
                <p class="text-sm text-base-content mt-0.5 leading-relaxed whitespace-pre-wrap">{message.body}</p>

                <!-- Usage metadata for agent messages -->
                {#if message.sender_role === 'agent' && message.metadata && message.metadata.total_cost_usd}
                  <div class="text-xs text-base-content/60 mt-2 flex gap-3 flex-wrap">
                    {#if message.metadata.total_cost_usd}
                      <span title="Total cost">${message.metadata.total_cost_usd.toFixed(4)}</span>
                    {/if}
                    {#if message.metadata.usage?.input_tokens}
                      <span title="Input tokens">{message.metadata.usage.input_tokens} in</span>
                    {/if}
                    {#if message.metadata.usage?.output_tokens}
                      <span title="Output tokens">{message.metadata.usage.output_tokens} out</span>
                    {/if}
                    {#if message.metadata.duration_ms}
                      <span title="Duration">{(message.metadata.duration_ms / 1000).toFixed(1)}s</span>
                    {/if}
                    {#if message.metadata.num_turns}
                      <span title="Number of turns">{message.metadata.num_turns} turns</span>
                    {/if}
                  </div>
                {/if}
              </div>
            </div>
          </div>
        {/each}
      {:else}
        <div class="empty-state">
          <div class="empty-state-content">
            <div class="empty-icon">
              <span style="width: 2.5rem; height: 2.5rem; color: #9ca3af; display: block;">{@html ChatBubbleLeftSvg}</span>
            </div>
            <h3 style="font-size: 1.125rem; font-weight: 600; color: #374151;">No messages yet</h3>
            <p style="font-size: 0.875rem; color: #6b7280; margin-top: 0.25rem;">
              Messages from agents will appear here
            </p>
          </div>
        </div>
      {/if}
    </div>

    <!-- Input Area -->
    <div class="input-area">
      <form on:submit|preventDefault={handleSubmit} class="input-form" style="position: relative;">
        <input
          type="text"
          bind:value={inputValue}
          bind:this={inputElement}
          on:input={handleInputChange}
          on:keydown={handleInputKeydown}
          placeholder="Send instruction to agents (use @id for direct messages)..."
          class="message-input"
          autocomplete="off"
        />

        <!-- Autocomplete Dropdown -->
        {#if showAutocomplete && autocompleteOptions.length > 0}
          <div class="autocomplete-dropdown">
            {#each autocompleteOptions as option, idx}
              <button
                type="button"
                class="autocomplete-item"
                class:selected={idx === selectedAutocompleteIndex}
                on:click={() => selectAutocomplete(option.id)}
                on:mouseenter={() => selectedAutocompleteIndex = idx}
              >
                <span class="autocomplete-id">@{option.id}</span>
                <span class="autocomplete-name">{option.name}</span>
                <span class="autocomplete-provider">{option.provider}{option.model ? ` / ${option.model}` : ''}</span>
              </button>
            {/each}
          </div>
        {/if}

        <button type="submit" class="send-button" disabled={!inputValue || inputValue.trim() === ''}>
          Send
        </button>
      </form>
    </div>
  </div>
</div>
