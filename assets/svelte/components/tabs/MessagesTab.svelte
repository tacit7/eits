<script>
  import { formatTime, formatDateRelative } from '../../utils/datetime.js'
  import { autoScroll } from '../../actions/autoScroll.js'

  // Heroicons
  import ChatBubbleLeftSvg from 'heroicons/24/outline/chat-bubble-left.svg'
  import CheckSvg from 'heroicons/24/outline/check.svg'
  import ComputerDesktopSvg from 'heroicons/24/outline/computer-desktop.svg'

  export let messages
  export let live

  $: console.log('Messages received:', messages)

  let selectedProvider = 'claude'

  function handleSubmit(e) {
    const formData = new FormData(e.target)
    const body = formData.get('body')

    if (body.trim()) {
      live.pushEvent('send_message', { body, provider: selectedProvider })
      e.target.reset()
    }
  }

  function selectProvider(provider) {
    selectedProvider = provider
  }
</script>

<style>
  .messages-container {
    display: flex;
    flex-direction: column;
    height: 600px;
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
</style>

<div class="messages-container">
  <!-- Messages scroll area -->
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
                {message.sender_role === 'user' ? 'You' : message.sender_role === 'agent' ? 'Agent' : message.sender_role}
              </h3>
              {#if message.provider}
                <span class="badge badge-xs badge-ghost">{message.provider}</span>
              {/if}
              <time class="text-xs opacity-50 ml-auto">{formatTime(message.inserted_at)}</time>
            </div>
            <p class="text-sm whitespace-pre-wrap">{message.body}</p>
          </div>
        </div>
      {/each}
    {:else}
      <!-- Empty state -->
      <div class="flex items-center justify-center h-full">
        <div class="text-center max-w-md">
          <span class="w-12 h-12 mx-auto mb-4 text-base-content/30 block">{@html ChatBubbleLeftSvg}</span>
          <h3 class="text-lg font-semibold text-base-content">No messages yet</h3>
          <p class="mt-1 text-sm text-base-content/70">
            Start a conversation with the agent below
          </p>
        </div>
      </div>
    {/if}
  </div>

  <!-- Input area -->
  <div class="border-t border-base-300 p-4">
    <form on:submit|preventDefault={handleSubmit} class="flex items-center gap-2">
      <!-- Provider selector dropdown -->
      <div class="dropdown dropdown-top">
        <label tabindex="0" class="btn btn-ghost btn-sm gap-2" title="Select AI Provider">
          <span class="w-4 h-4">{@html ComputerDesktopSvg}</span>
          <span class="badge badge-sm badge-primary">{selectedProvider}</span>
        </label>
        <ul tabindex="0" class="dropdown-content menu p-2 shadow bg-base-100 rounded-box w-40 mb-2">
          <li>
            <button type="button" on:click={() => selectProvider('claude')}
              class="flex items-center justify-between">
              <span>Claude</span>
              {#if selectedProvider === 'claude'}
                <span class="w-4 h-4">{@html CheckSvg}</span>
              {/if}
            </button>
          </li>
          <li>
            <button type="button" on:click={() => selectProvider('openai')}
              class="flex items-center justify-between">
              <span>OpenAI</span>
              {#if selectedProvider === 'openai'}
                <span class="w-4 h-4">{@html CheckSvg}</span>
              {/if}
            </button>
          </li>
        </ul>
      </div>

      <!-- Message input -->
      <input
        type="text"
        name="body"
        placeholder="Send instruction to agent..."
        class="input input-bordered flex-1"
        autocomplete="off"
      />

      <!-- Send button -->
      <button type="submit" class="btn btn-primary btn-sm" aria-label="Send message">
        <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
          <path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/>
        </svg>
      </button>
    </form>
  </div>
</div>
