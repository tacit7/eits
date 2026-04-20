<script>
  import { onMount } from 'svelte'

  export let live

  let bookmarkedAgents = []
  let selectedAgent = null
  let showChatModal = false

  // Chat state
  let messages = []
  let inputValue = ''

  const MAX_BOOKMARKS = 4

  onMount(() => {
    loadBookmarks()

    // Listen for bookmark changes from other components
    window.addEventListener('bookmarks-updated', handleBookmarksUpdated)

    return () => {
      window.removeEventListener('bookmarks-updated', handleBookmarksUpdated)
    }
  })

  function loadBookmarks() {
    try {
      const stored = localStorage.getItem('eye-in-the-sky-bookmarks')
      if (stored) {
        bookmarkedAgents = JSON.parse(stored)
      }
    } catch (e) {
      console.error('Failed to load bookmarks:', e)
      bookmarkedAgents = []
    }
  }

  function handleBookmarksUpdated(event) {
    loadBookmarks()
  }

  function handleAgentClick(agent) {
    selectedAgent = agent
    showChatModal = true
    messages = []
  }

  function closeChatModal() {
    showChatModal = false
    selectedAgent = null
    messages = []
    inputValue = ''
  }

  function handleSubmit() {
    if (!inputValue.trim() || !selectedAgent) return

    // Send message via LiveView
    live.pushEvent('send_direct_message', {
      session_id: selectedAgent.session_id,
      body: inputValue.trim()
    })

    // Add message to local display immediately (optimistic update)
    messages = [...messages, {
      body: inputValue.trim(),
      sender_role: 'user',
      inserted_at: new Date().toISOString()
    }]

    inputValue = ''
  }

  function getAgentInitials(name) {
    if (!name) return '?'
    return name.split(' ').map(w => w[0]).join('').substring(0, 2).toUpperCase()
  }

  function getStatusBadgeClass(status) {
    switch(status) {
      case 'active': return 'badge-success'
      case 'idle': return 'badge-info'
      case 'working': return 'badge-warning'
      default: return 'badge-ghost'
    }
  }
</script>

<!-- DaisyUI FAB with Flower Layout -->
<div class="fab fab-flower" class:opacity-50={bookmarkedAgents.length === 0}>
  <div
    tabindex="0"
    role="button"
    class="btn btn-lg btn-circle"
    class:btn-primary={bookmarkedAgents.length > 0}
    class:btn-disabled={bookmarkedAgents.length === 0}
  >
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6">
      <path d="M4.913 2.658c2.075-.27 4.19-.408 6.337-.408 2.147 0 4.262.139 6.337.408 1.922.25 3.291 1.861 3.405 3.727a4.403 4.403 0 00-1.032-.211 50.89 50.89 0 00-8.42 0c-2.358.196-4.04 2.19-4.04 4.434v4.286a4.47 4.47 0 002.433 3.984L7.28 21.53A.75.75 0 016 21v-4.03a48.527 48.527 0 01-1.087-.128C2.905 16.58 1.5 14.833 1.5 12.862V6.638c0-1.97 1.405-3.718 3.413-3.979z" />
      <path d="M15.75 7.5c-1.376 0-2.739.057-4.086.169C10.124 7.797 9 9.103 9 10.609v4.285c0 1.507 1.128 2.814 2.67 2.94 1.243.102 2.5.157 3.768.165l2.782 2.781a.75.75 0 001.28-.53v-2.39l.33-.026c1.542-.125 2.67-1.433 2.67-2.94v-4.286c0-1.505-1.125-2.811-2.664-2.94A49.392 49.392 0 0015.75 7.5z" />
    </svg>

    {#if bookmarkedAgents.length > 0}
      <span class="badge badge-sm badge-error absolute top-0 right-0">{bookmarkedAgents.length}</span>
    {/if}
  </div>

  <!-- Agent Buttons -->
  {#each bookmarkedAgents as agent, index}
    <button
      class="btn btn-circle btn-sm relative"
      on:click={() => handleAgentClick(agent)}
      title={agent.name || agent.session_id}
    >
      <span class="font-bold text-xs">{getAgentInitials(agent.name)}</span>
      <span class="badge {getStatusBadgeClass(agent.status)} badge-xs absolute -bottom-1 -right-1"></span>
    </button>
  {/each}
</div>

<!-- DaisyUI Modal for Chat -->
{#if showChatModal && selectedAgent}
  <dialog class="modal modal-open">
    <div class="modal-box max-w-lg">
      <!-- Header -->
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center gap-2">
          <h3 class="font-bold text-lg">{selectedAgent.name || 'Agent'}</h3>
          <span class="badge badge-sm badge-outline font-mono">{selectedAgent.session_id.substring(0, 8)}</span>
        </div>
        <button class="btn btn-sm btn-circle btn-ghost" on:click={closeChatModal}>✕</button>
      </div>

      <!-- Messages Area -->
      <div class="bg-base-200 rounded-lg p-4 h-96 overflow-y-auto mb-4">
        {#if messages.length === 0}
          <div class="text-center text-base-content/50 py-8">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-12 h-12 mx-auto mb-2 opacity-30">
              <path stroke-linecap="round" stroke-linejoin="round" d="M8.625 12a.375.375 0 11-.75 0 .375.375 0 01.75 0zm0 0H8.25m4.125 0a.375.375 0 11-.75 0 .375.375 0 01.75 0zm0 0H12m4.125 0a.375.375 0 11-.75 0 .375.375 0 01.75 0zm0 0h-.375M21 12c0 4.556-4.03 8.25-9 8.25a9.764 9.764 0 01-2.555-.337A5.972 5.972 0 015.41 20.97a5.969 5.969 0 01-.474-.065 4.48 4.48 0 00.978-2.025c.09-.457-.133-.901-.467-1.226C3.93 16.178 3 14.189 3 12c0-4.556 4.03-8.25 9-8.25s9 3.694 9 8.25z" />
            </svg>
            <p class="text-sm">No messages yet. Start a conversation!</p>
          </div>
        {:else}
          <div class="space-y-0">
            {#each messages as message}
              <div class="group py-2 px-1 rounded-lg hover:bg-base-content/[0.02] transition-colors">
                <div class="flex items-start gap-2">
                  {#if message.sender_role === 'user'}
                    <div class="w-3.5 h-3.5 rounded-full mt-1 flex-shrink-0 bg-success/20 flex items-center justify-center">
                      <div class="w-1 h-1 rounded-full bg-success"></div>
                    </div>
                  {:else}
                    <div class="w-3.5 h-3.5 rounded-full mt-1 flex-shrink-0 bg-primary/20 flex items-center justify-center">
                      <div class="w-1 h-1 rounded-full bg-primary/60"></div>
                    </div>
                  {/if}
                  <div class="min-w-0 flex-1">
                    <span class="text-[11px] font-semibold {message.sender_role === 'user' ? 'text-base-content/60' : 'text-primary/70'} mr-1.5">
                      {message.sender_role === 'user' ? 'You' : 'Agent'}
                    </span>
                    <p class="text-sm leading-relaxed text-base-content/85 whitespace-pre-wrap break-words mt-0.5">{message.body}</p>
                  </div>
                </div>
              </div>
            {/each}
          </div>
        {/if}
      </div>

      <!-- Input Area -->
      <form on:submit|preventDefault={handleSubmit} class="flex gap-2">
        <input
          type="text"
          class="input input-bordered flex-1"
          placeholder="Send message to agent..."
          bind:value={inputValue}
          autocomplete="off"
        />
        <button type="submit" class="btn btn-primary" disabled={!inputValue.trim()} aria-label="Send">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5">
            <path d="M3.478 2.405a.75.75 0 00-.926.94l2.432 7.905H13.5a.75.75 0 010 1.5H4.984l-2.432 7.905a.75.75 0 00.926.94 60.519 60.519 0 0018.445-8.986.75.75 0 000-1.218A60.517 60.517 0 003.478 2.405z" />
          </svg>
        </button>
      </form>
    </div>
    <!-- svelte-ignore a11y_no_noninteractive_element_interactions a11y_click_events_have_key_events -->
    <form method="dialog" class="modal-backdrop" on:click={closeChatModal}>
      <button>close</button>
    </form>
  </dialog>
{/if}
