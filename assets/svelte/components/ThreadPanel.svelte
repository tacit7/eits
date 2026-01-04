<script>
  import { createEventDispatcher } from 'svelte'
  import { formatTime } from '../utils/datetime.js'

  export let thread = null
  export let live

  const dispatch = createEventDispatcher()

  function handleSubmit(e) {
    const formData = new FormData(e.target)
    const body = formData.get('body')

    if (body.trim() && thread && thread.parent_message) {
      live.pushEvent('send_thread_reply', {
        parent_message_id: thread.parent_message.id,
        body: body
      })
      e.target.reset()
    }
  }

  function close() {
    dispatch('close')
  }
</script>

<style>
  .thread-panel {
    width: 400px;
    height: 100%;
    background-color: white;
    border-left: 1px solid #ddd;
    display: flex;
    flex-direction: column;
    box-shadow: -2px 0 8px rgba(0, 0, 0, 0.1);
  }

  :global(.dark) .thread-panel {
    background-color: #1a1d21;
    border-left-color: #2f3437;
  }

  .thread-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1rem 1.25rem;
    border-bottom: 1px solid #ddd;
  }

  :global(.dark) .thread-header {
    border-bottom-color: #2f3437;
  }

  .thread-title {
    font-size: 1.125rem;
    font-weight: 700;
    color: #1d1c1d;
  }

  :global(.dark) .thread-title {
    color: #f8f8f8;
  }

  .close-button {
    background: none;
    border: none;
    font-size: 1.5rem;
    color: #616061;
    cursor: pointer;
    padding: 0;
    width: 2rem;
    height: 2rem;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 0.25rem;
  }

  .close-button:hover {
    background-color: #f8f8f8;
    color: #1d1c1d;
  }

  :global(.dark) .close-button:hover {
    background-color: #2f3437;
    color: #f8f8f8;
  }

  .thread-content {
    flex: 1;
    overflow-y: auto;
    padding: 1rem 1.25rem;
  }

  .parent-message {
    padding: 1rem;
    background-color: #f8f8f8;
    border-radius: 0.5rem;
    margin-bottom: 1.5rem;
  }

  :global(.dark) .parent-message {
    background-color: #222529;
  }

  .message-header {
    display: flex;
    align-items: baseline;
    gap: 0.5rem;
    margin-bottom: 0.5rem;
  }

  .sender-name {
    font-weight: 700;
    font-size: 0.9375rem;
    color: #1d1c1d;
  }

  :global(.dark) .sender-name {
    color: #f8f8f8;
  }

  .message-time {
    font-size: 0.75rem;
    color: #616061;
  }

  :global(.dark) .message-time {
    color: #949699;
  }

  .message-body {
    font-size: 0.9375rem;
    color: #1d1c1d;
    white-space: pre-wrap;
    word-break: break-word;
    line-height: 1.5;
  }

  :global(.dark) .message-body {
    color: #dcddde;
  }

  .replies-section {
    border-top: 1px solid #ddd;
    padding-top: 1rem;
  }

  :global(.dark) .replies-section {
    border-top-color: #2f3437;
  }

  .reply-count {
    font-size: 0.875rem;
    font-weight: 600;
    color: #616061;
    margin-bottom: 1rem;
  }

  :global(.dark) .reply-count {
    color: #949699;
  }

  .reply {
    margin-bottom: 1rem;
    padding: 0.75rem;
    border-radius: 0.375rem;
  }

  .reply:hover {
    background-color: #f8f8f8;
  }

  :global(.dark) .reply:hover {
    background-color: #222529;
  }

  .thread-input-area {
    border-top: 1px solid #ddd;
    padding: 1rem 1.25rem;
  }

  :global(.dark) .thread-input-area {
    border-top-color: #2f3437;
  }

  .input-form {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .thread-input {
    width: 100%;
    padding: 0.75rem;
    border-radius: 0.375rem;
    background-color: white;
    border: 1px solid #ddd;
    font-size: 0.9375rem;
    color: #1d1c1d;
    resize: vertical;
    min-height: 3rem;
  }

  .thread-input:focus {
    outline: 2px solid #1264a3;
    outline-offset: 0;
    border-color: transparent;
  }

  :global(.dark) .thread-input {
    background-color: #2f3437;
    border-color: #2f3437;
    color: #f8f8f8;
  }

  .send-button {
    align-self: flex-end;
    padding: 0.5rem 1rem;
    border-radius: 0.375rem;
    background-color: #007a5a;
    border: none;
    color: white;
    font-weight: 600;
    font-size: 0.875rem;
    cursor: pointer;
    transition: background-color 0.15s;
  }

  .send-button:hover {
    background-color: #006644;
  }

  .empty-replies {
    text-align: center;
    padding: 2rem 1rem;
    color: #616061;
    font-size: 0.875rem;
  }

  :global(.dark) .empty-replies {
    color: #949699;
  }
</style>

<div class="thread-panel">
  <!-- Thread Header -->
  <div class="thread-header">
    <div class="thread-title">Thread</div>
    <button class="close-button" on:click={close} aria-label="Close thread">
      ×
    </button>
  </div>

  <!-- Thread Content -->
  <div class="thread-content">
    {#if thread && thread.parent_message}
      <!-- Parent Message -->
      <div class="parent-message">
        <div class="message-header">
          <span class="sender-name">
            {thread.parent_message.sender_role === 'user' ? 'You' : `Agent (${thread.parent_message.provider || 'unknown'})`}
          </span>
          <span class="message-time">{formatTime(thread.parent_message.inserted_at)}</span>
        </div>
        <div class="message-body">{thread.parent_message.body}</div>
      </div>

      <!-- Replies Section -->
      <div class="replies-section">
        {#if thread.replies && thread.replies.length > 0}
          <div class="reply-count">
            {thread.replies.length} {thread.replies.length === 1 ? 'reply' : 'replies'}
          </div>

          {#each thread.replies as reply}
            <div class="reply">
              <div class="message-header">
                <span class="sender-name">
                  {reply.sender_role === 'user' ? 'You' : `Agent (${reply.provider || 'unknown'})`}
                </span>
                <span class="message-time">{formatTime(reply.inserted_at)}</span>
              </div>
              <div class="message-body">{reply.body}</div>
            </div>
          {/each}
        {:else}
          <div class="empty-replies">
            No replies yet. Start the conversation below.
          </div>
        {/if}
      </div>
    {/if}
  </div>

  <!-- Thread Input Area -->
  <div class="thread-input-area">
    <form on:submit|preventDefault={handleSubmit} class="input-form">
      <textarea
        name="body"
        placeholder="Reply to thread..."
        class="thread-input"
        rows="2"
      ></textarea>

      <button type="submit" class="send-button">
        Send
      </button>
    </form>
  </div>
</div>
