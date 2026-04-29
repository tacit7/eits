<script>
  import { formatTime } from '../utils/datetime.js'
  import { marked } from 'marked'
  import DOMPurify from 'dompurify'

  export let thread = null
  export let live

  marked.setOptions({ gfm: true, breaks: true })

  const DOMPURIFY_CONFIG = {
    ALLOWED_TAGS: ['p', 'strong', 'em', 'b', 'i', 'code', 'pre', 'ul', 'ol', 'li',
                   'br', 'h1', 'h2', 'h3', 'h4', 'blockquote', 'a', 'span', 'hr', 'del'],
    ALLOWED_ATTR: ['class', 'href', 'target', 'rel']
  }

  function renderBody(body) {
    if (!body) return ''
    const html = marked.parse(body)
    return DOMPurify.sanitize(html, DOMPURIFY_CONFIG)
  }

  function senderLabel(message) {
    if (!message) return ''
    if (message.sender_role === 'user') return 'You'
    return message.session_name || `@${message.session_id}` || message.provider || 'Agent'
  }

  let replyInput = ''

  function handleSubmit(e) {
    e.preventDefault()
    if (!replyInput.trim() || !thread?.parent_message) return
    live.pushEvent('send_thread_reply', {
      parent_message_id: String(thread.parent_message.id),
      body: replyInput.trim()
    })
    replyInput = ''
  }

  function handleKeydown(e) {
    if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
      handleSubmit(e)
    }
  }

  function close() {
    live.pushEvent('close_thread', {})
  }
</script>

<style>
  :global(.thread-body p) { margin-bottom: 0.35em; }
  :global(.thread-body p:last-child) { margin-bottom: 0; }
  :global(.thread-body ol) { list-style-type: decimal; padding-left: 1.3em; margin: 0.25em 0 0.4em; }
  :global(.thread-body ul) { list-style-type: disc; padding-left: 1.3em; margin: 0.25em 0 0.4em; }
  :global(.thread-body li) { line-height: 1.5; margin-bottom: 0.15em; }
  :global(.thread-body code:not(pre code)) {
    font-family: ui-monospace, monospace;
    font-size: 0.8em;
    padding: 0.1em 0.3em;
    border-radius: 3px;
    background-color: rgb(127 127 127 / 0.1);
  }
  :global(.thread-body pre) {
    font-family: ui-monospace, monospace;
    font-size: 0.8em;
    padding: 0.6em 0.8em;
    border-radius: 5px;
    background-color: rgb(127 127 127 / 0.07);
    overflow-x: auto;
    margin: 0.35em 0;
  }
  :global(.thread-body pre code) { background: none; padding: 0; font-size: 1em; }
  :global(.thread-body strong, .thread-body b) { font-weight: 600; }
  :global(.thread-body em, .thread-body i) { font-style: italic; }
</style>

<div class="flex flex-col h-full w-[360px] flex-shrink-0 border-l border-base-content/8 bg-base-100">

  <!-- Header -->
  <div class="flex items-center justify-between px-4 py-3 border-b border-base-content/8 flex-shrink-0">
    <div class="flex items-center gap-2">
      <svg class="w-3.5 h-3.5 text-base-content/40" viewBox="0 0 20 20" fill="currentColor">
        <path fill-rule="evenodd" d="M2 5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H6l-4 4V5Z" clip-rule="evenodd"/>
      </svg>
      <span class="text-sm font-semibold text-base-content/70">Thread</span>
    </div>
    <button
      on:click={close}
      class="w-6 h-6 flex items-center justify-center rounded text-base-content/30 hover:text-base-content/70 hover:bg-base-content/5 transition-colors"
      aria-label="Close thread"
    >
      <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor">
        <path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z"/>
      </svg>
    </button>
  </div>

  <!-- Content -->
  <div class="flex-1 overflow-y-auto" style="scrollbar-width: none;">

    {#if thread && thread.parent_message}
      <!-- Parent message -->
      <div class="px-4 pt-4 pb-3 border-b border-base-content/5">
        <div class="flex items-baseline gap-2 mb-1.5">
          <span class="text-[13px] font-semibold text-primary/80">
            {senderLabel(thread.parent_message)}
          </span>
          <span class="text-[11px] text-base-content/25">
            {formatTime(thread.parent_message.inserted_at)}
          </span>
        </div>
        <div class="thread-body text-sm leading-relaxed text-base-content/80 break-words">
          {@html renderBody(thread.parent_message.body)}
        </div>
      </div>

      <!-- Replies -->
      <div class="px-4 pt-3">
        {#if thread.replies && thread.replies.length > 0}
          <div class="text-[11px] font-medium text-base-content/30 uppercase tracking-wider mb-3">
            {thread.replies.length} {thread.replies.length === 1 ? 'reply' : 'replies'}
          </div>
          {#each thread.replies as reply}
            <div class="mb-4">
              <div class="flex items-baseline gap-2 mb-1">
                <span class="text-[13px] font-semibold {reply.sender_role === 'user' ? 'text-base-content/70' : 'text-primary/80'}">
                  {senderLabel(reply)}
                </span>
                <span class="text-[11px] text-base-content/25">{formatTime(reply.inserted_at)}</span>
              </div>
              <div class="thread-body text-sm leading-relaxed text-base-content/80 break-words">
                {@html renderBody(reply.body)}
              </div>
            </div>
          {/each}
        {:else}
          <div class="py-8 text-center">
            <p class="text-xs text-base-content/30">No replies yet</p>
          </div>
        {/if}
      </div>
    {:else}
      <div class="flex items-center justify-center h-full">
        <p class="text-xs text-base-content/30">Loading thread…</p>
      </div>
    {/if}
  </div>

  <!-- Reply composer -->
  <div class="flex-shrink-0 p-3 border-t border-base-content/8">
    <form on:submit={handleSubmit}>
      <textarea
        bind:value={replyInput}
        on:keydown={handleKeydown}
        placeholder="Reply to thread… (⌘↵ to send)"
        rows="3"
        class="w-full textarea textarea-sm bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 text-sm resize-none focus:border-primary/30 focus:bg-base-100 transition-colors"
      ></textarea>
      <div class="flex justify-end mt-2">
        <button
          type="submit"
          class="btn btn-xs btn-primary"
          disabled={!replyInput || !replyInput.trim()}
        >
          Reply
        </button>
      </div>
    </form>
  </div>
</div>
