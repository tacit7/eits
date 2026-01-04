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
  export let live
  let inputValue = ''
  let inputElement

  // Modal state
  let showAgentModal = false
  let agentType = 'claude'
  let agentModel = 'sonnet'
  let agentDescription = ''
  let agentInstructions = ''
  let selectedPromptId = ''

  // Autocomplete state
  let showAutocomplete = false
  let autocompleteOptions = []
  let selectedAutocompleteIndex = 0

  // Message history for up/down navigation
  let messageHistory = []
  let historyIndex = -1
  let currentDraft = ''

  function openAgentModal() {
    showAgentModal = true
    agentType = 'claude'
    agentModel = 'sonnet'
    agentDescription = ''
    agentInstructions = ''
    selectedPromptId = ''
  }

  function closeAgentModal() {
    showAgentModal = false
  }

  function handlePromptChange(e) {
    selectedPromptId = e.target.value
    if (selectedPromptId) {
      const prompt = prompts.find(p => p.id === selectedPromptId)
      if (prompt && prompt.prompt_text) {
        agentInstructions = prompt.prompt_text
      }
    }
  }

  function createAgent() {
    live.pushEvent('create_agent', {
      agent_type: agentType,
      model: agentModel,
      description: agentDescription,
      instructions: agentInstructions,
      prompt_id: selectedPromptId || null,
      channel_id: activeChannelId
    })
    closeAgentModal()
  }

  function handleSessionIdClick(sessionId) {
    const shortId = sessionId.substring(0, 8)
    inputValue = `@${shortId} `
    showAutocomplete = false
    if (inputElement) {
      inputElement.focus()
    }
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
        // Get unique agent session IDs from messages
        const agentSessions = messages
          .filter(m => m.sender_role === 'agent' && m.session_id)
          .reduce((acc, m) => {
            if (!acc.some(s => s.id === m.session_id)) {
              acc.push({
                id: m.session_id,
                shortId: m.session_id.substring(0, 8),
                provider: m.provider || 'agent',
                name: m.session_name || null
              })
            }
            return acc
          }, [])

        // Filter based on what's typed after @ (search in ID, shortID, and name)
        const searchTerm = textAfterAt.toLowerCase()
        const filtered = agentSessions.filter(s =>
          s.id.toLowerCase().includes(searchTerm) ||
          s.shortId.toLowerCase().includes(searchTerm) ||
          (s.name && s.name.toLowerCase().includes(searchTerm))
        )

        if (filtered.length > 0) {
          autocompleteOptions = filtered
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

    // Handle message history navigation (up/down arrows when autocomplete is NOT shown)
    if (e.key === 'ArrowUp') {
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
    } else if (e.key === 'ArrowDown') {
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

    // Replace from @ to cursor with first 8 chars of session ID
    const shortId = sessionId.substring(0, 8)
    inputValue = textBeforeCursor.substring(0, lastAtIndex) + `@${shortId} ` + textAfterCursor
    showAutocomplete = false

    // Set cursor after the inserted text
    setTimeout(() => {
      const newPos = lastAtIndex + shortId.length + 2
      inputElement.setSelectionRange(newPos, newPos)
      inputElement.focus()
    }, 0)
  }

  function handleSubmit(e) {
    const body = inputValue.trim()

    if (body) {
      // Check for @session-id mentions (match first 8 chars or full UUID)
      const mentionRegex = /@([a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}|[a-f0-9]{8})/gi
      const mentions = []
      let match

      while ((match = mentionRegex.exec(body)) !== null) {
        const sessionIdPart = match[1]
        // Find full session_id from messages that match the prefix
        const fullSessionId = messages.find(m =>
          m.session_id && m.session_id.startsWith(sessionIdPart)
        )?.session_id || sessionIdPart

        if (!mentions.includes(fullSessionId)) {
          mentions.push(fullSessionId)
        }
      }

      if (mentions.length > 0) {
        // Send targeted message to each mentioned agent
        mentions.forEach(sessionId => {
          live.pushEvent('send_direct_message', {
            session_id: sessionId,
            body: body,
            channel_id: activeChannelId
          })
        })
      } else {
        // Regular broadcast message to channel
        live.pushEvent('send_channel_message', {
          channel_id: activeChannelId,
          body: body
        })
      }

      // Add to message history (at beginning of array for reverse chronological)
      messageHistory.unshift(body)
      // Keep only last 50 messages in history
      if (messageHistory.length > 50) {
        messageHistory = messageHistory.slice(0, 50)
      }

      // Reset history navigation
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
  }

  .session-id-badge:hover {
    transform: scale(1.05);
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
        <button class="new-agent-btn" on:click={openAgentModal}>
          + New Agent
        </button>
      </div>
    </div>

    <!-- Messages Container -->
    <div
      use:autoScroll={{ trigger: messages?.length }}
      class="messages-scroll"
    >
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

          <!-- Message card -->
          <div class="card bg-base-100 shadow-sm mb-3 {message.sender_role === 'user' ? 'border-l-4 border-primary' : 'border-l-4 border-base-300'}">
            <div class="card-body p-4">
              <div class="flex items-center gap-2 mb-2">
                <h3 class="card-title text-sm">
                  {message.sender_role === 'user' ? 'You' : `Agent (${message.provider || 'unknown'})`}
                </h3>
                <time class="text-xs opacity-50">{formatTime(message.inserted_at)}</time>
                {#if message.sender_role === 'agent' && message.session_id}
                  <span
                    class="badge badge-xs badge-outline session-id-badge ml-auto"
                    on:click={() => handleSessionIdClick(message.session_id)}
                    on:keydown={(e) => e.key === 'Enter' && handleSessionIdClick(message.session_id)}
                    role="button"
                    tabindex="0"
                  >
                    {message.session_id.substring(0, 8)}
                  </span>
                {/if}
              </div>
              <p class="text-sm whitespace-pre-wrap">{message.body}</p>
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
          placeholder="Send instruction to agents (use @session-id for direct messages)..."
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
                <span class="autocomplete-id">@{option.shortId}</span>
                {#if option.name}
                  <span class="autocomplete-name">{option.name}</span>
                {/if}
                <span class="autocomplete-provider">({option.provider})</span>
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

  <!-- Agent Creation Modal -->
  {#if showAgentModal}
    <dialog class="modal modal-open">
      <div class="modal-box">
        <h3 class="font-bold text-lg mb-4">Create New Agent</h3>

        <!-- Agent Type -->
        <div class="form-control w-full mb-4">
          <label class="label" for="agent-type">
            <span class="label-text">Agent Type</span>
          </label>
          <select id="agent-type" class="select select-bordered w-full" bind:value={agentType}>
            <option value="claude">Claude</option>
            <option value="codex">Codex</option>
          </select>
        </div>

        <!-- Model -->
        <div class="form-control w-full mb-4">
          <label class="label" for="model">
            <span class="label-text">Model</span>
          </label>
          <select id="model" class="select select-bordered w-full" bind:value={agentModel}>
            {#if agentType === 'claude'}
              <option value="sonnet">Sonnet</option>
              <option value="opus">Opus</option>
              <option value="haiku">Haiku</option>
            {:else}
              <option value="gpt-4">GPT-4</option>
              <option value="gpt-3.5-turbo">GPT-3.5 Turbo</option>
            {/if}
          </select>
        </div>

        <!-- Description/Nickname -->
        <div class="form-control w-full mb-4">
          <label class="label" for="description">
            <span class="label-text">Agent Name / Nickname</span>
          </label>
          <input
            id="description"
            type="text"
            class="input input-bordered w-full"
            placeholder="e.g., Code Reviewer, Bug Fixer, Feature Dev..."
            bind:value={agentDescription}
          />
        </div>

        <!-- Prompt Template -->
        <div class="form-control w-full mb-4">
          <label class="label" for="prompt">
            <span class="label-text">Prompt Template (Optional)</span>
          </label>
          <select
            id="prompt"
            class="select select-bordered w-full"
            bind:value={selectedPromptId}
            on:change={handlePromptChange}
          >
            <option value="">-- None (Custom Instructions) --</option>
            {#each prompts as prompt}
              <option value={prompt.id}>{prompt.name}</option>
            {/each}
          </select>
          {#if selectedPromptId}
            <label class="label">
              <span class="label-text-alt text-info">
                {prompts.find(p => p.id === selectedPromptId)?.description || ''}
              </span>
            </label>
          {/if}
        </div>

        <!-- Instructions -->
        <div class="form-control w-full mb-4">
          <label class="label" for="instructions">
            <span class="label-text">Instructions</span>
          </label>
          <textarea
            id="instructions"
            class="textarea textarea-bordered h-24"
            placeholder="Enter agent instructions..."
            bind:value={agentInstructions}
          ></textarea>
        </div>

        <div class="modal-action">
          <button class="btn" on:click={closeAgentModal}>Cancel</button>
          <button class="btn btn-primary" on:click={createAgent}>Create</button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button on:click={closeAgentModal}>close</button>
      </form>
    </dialog>
  {/if}
</div>
