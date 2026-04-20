<script>
  import { formatTime, formatDateRelative } from '../../utils/datetime.js'
  import { autoScroll } from '../../actions/autoScroll.js'

  // Heroicons
  import ChatBubbleLeftSvg from 'heroicons/24/outline/chat-bubble-left.svg'
  import CheckSvg from 'heroicons/24/outline/check.svg'
  import ComputerDesktopSvg from 'heroicons/24/outline/computer-desktop.svg'

  export let messages
  export let live

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

<div class="flex flex-col h-[600px]">
  <!-- Messages scroll area -->
  <div
    use:autoScroll={{ trigger: messages?.length }}
    class="flex-1 overflow-y-auto px-6 py-4"
  >
    {#if messages && messages.length > 0}
      {#each messages as message, idx}
        <!-- Date separator -->
        {#if idx === 0 || formatDateRelative(messages[idx - 1].inserted_at) !== formatDateRelative(message.inserted_at)}
          <div class="flex items-center justify-center my-6">
            <div class="badge badge-ghost badge-sm text-xs font-semibold px-3 py-1">
              {formatDateRelative(message.inserted_at)}
            </div>
          </div>
        {/if}

        <!-- Message row -->
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
              <div class="flex items-baseline gap-1.5 mb-0.5">
                <span class="text-[11px] font-semibold {message.sender_role === 'user' ? 'text-base-content/60' : 'text-primary/70'}">
                  {message.sender_role === 'user' ? 'You' : message.sender_role === 'agent' ? 'Agent' : message.sender_role}
                </span>
                {#if message.provider}
                  <span class="badge badge-xs badge-ghost">{message.provider}</span>
                {/if}
                <time class="text-[10px] text-base-content/30 ml-auto">{formatTime(message.inserted_at)}</time>
              </div>
              <p class="text-sm leading-relaxed text-base-content/85 whitespace-pre-wrap break-words">{message.body}</p>
            </div>
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
        <button type="button" tabindex="0" class="btn btn-ghost btn-sm gap-2" title="Select AI Provider">
          <span class="w-4 h-4">{@html ComputerDesktopSvg}</span>
          <span class="badge badge-sm badge-primary">{selectedProvider}</span>
        </button>
        <ul class="dropdown-content menu p-2 shadow bg-base-100 rounded-box w-40 mb-2">
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
