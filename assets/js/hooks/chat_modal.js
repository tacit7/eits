/**
 * ChatModal — shared factory class for in-page chat modals.
 *
 * Config:
 *   id              {string}   — DOM id for the modal root (required)
 *   title           {string}   — header title text
 *   initials        {string}   — avatar letters (1–2 chars)
 *   subtitle        {string=}  — status label shown next to title
 *   subtitleClass   {string=}  — extra CSS classes for the subtitle span
 *   placeholder     {string=}  — input placeholder text
 *   dmHref          {string=}  — URL for the "open full DM" link button
 *   errorCloseButton {boolean=} — show a Close button inside error bubbles
 *   onSend          {fn(body)} — called with trimmed body when user sends
 *   onClose         {fn()}     — called when the close button is clicked
 */
export class ChatModal {
  constructor(config) {
    this._id = config.id
    this._cfg = config
    this._inputEl = null
    this._messagesEl = null
  }

  /** Build and append the modal to document.body. No-op if already present. */
  create() {
    if (document.getElementById(this._id)) return this
    const modal = document.createElement('div')
    modal.id = this._id
    modal.innerHTML = this._buildHtml()
    document.body.appendChild(modal)
    this._inputEl = modal.querySelector(`#${this._id}-input`)
    this._messagesEl = modal.querySelector(`#${this._id}-messages`)
    this._bindEvents(modal)
    return this
  }

  /** Append a single message bubble and scroll to bottom. */
  appendMessage(msg) {
    if (!this._messagesEl) return
    this._messagesEl.querySelector(`#${this._id}-loading, #${this._id}-empty`)?.remove()
    const div = document.createElement('div')
    div.innerHTML = this._messageHtml(msg)
    this._messagesEl.appendChild(div.firstChild)
    this._messagesEl.scrollTop = this._messagesEl.scrollHeight
  }

  /** Replace all messages in the container. */
  setMessages(messages, emptyText = 'No messages yet') {
    if (!this._messagesEl) return
    if (messages.length === 0) {
      this._messagesEl.innerHTML = `<div id="${this._id}-empty" class="text-center text-base-content/25 text-xs py-10">${emptyText}</div>`
    } else {
      this._messagesEl.innerHTML = messages.map(m => this._messageHtml(m)).join('')
    }
    this._messagesEl.scrollTop = this._messagesEl.scrollHeight
  }

  /** Focus the message input. */
  focusInput() {
    this._inputEl?.focus()
  }

  /** Remove the modal from the DOM. */
  destroy() {
    document.getElementById(this._id)?.remove()
    this._inputEl = null
    this._messagesEl = null
  }

  /** True if the modal is currently in the DOM. */
  exists() {
    return !!document.getElementById(this._id)
  }

  /** HTML-escape a string for safe insertion into markup. */
  static escape(str) {
    const div = document.createElement('div')
    div.textContent = str
    return div.innerHTML
  }

  // ── private ────────────────────────────────────────────────────────────────

  _buildHtml() {
    const { title, initials, subtitle, subtitleClass, placeholder, dmHref } = this._cfg

    const subtitleHtml = subtitle != null
      ? `<span id="${this._id}-subtitle" class="text-xs font-medium uppercase tracking-wider ml-1.5 ${subtitleClass || ''}">${ChatModal.escape(subtitle)}</span>`
      : ''

    const dmLinkHtml = dmHref
      ? `<a href="${ChatModal.escape(dmHref)}" class="btn btn-ghost btn-xs btn-square text-base-content/30 hover:text-primary" title="Open full DM">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
            <path fill-rule="evenodd" d="M4.25 5.5a.75.75 0 0 0-.75.75v8.5c0 .414.336.75.75.75h8.5a.75.75 0 0 0 .75-.75v-4a.75.75 0 0 1 1.5 0v4A2.25 2.25 0 0 1 12.75 17h-8.5A2.25 2.25 0 0 1 2 14.75v-8.5A2.25 2.25 0 0 1 4.25 4h5a.75.75 0 0 1 0 1.5h-5Z" clip-rule="evenodd" />
            <path fill-rule="evenodd" d="M6.194 12.753a.75.75 0 0 0 1.06.053L16.5 4.44v2.81a.75.75 0 0 0 1.5 0v-4.5a.75.75 0 0 0-.75-.75h-4.5a.75.75 0 0 0 0 1.5h2.553l-9.056 8.194a.75.75 0 0 0-.053 1.06Z" clip-rule="evenodd" />
          </svg>
        </a>`
      : ''

    return `
      <div class="fixed bottom-24 right-4 w-[520px] z-[1000] flex flex-col bg-base-100 border border-base-content/10 rounded-xl shadow-2xl max-h-[850px] overflow-hidden">
        <div class="flex items-center justify-between px-4 py-2.5 border-b border-base-content/5 bg-base-200/30">
          <div class="flex items-center gap-2">
            <span class="font-bold text-xs bg-primary/10 text-primary rounded-full w-7 h-7 flex items-center justify-center">${ChatModal.escape(initials)}</span>
            <div>
              <span class="text-xs font-semibold text-base-content/70">${ChatModal.escape(title)}</span>
              ${subtitleHtml}
            </div>
          </div>
          <div class="flex items-center gap-1">
            ${dmLinkHtml}
            <button id="${this._id}-close" class="btn btn-ghost btn-xs btn-square text-base-content/30" title="Close">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                <path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z" />
              </svg>
            </button>
          </div>
        </div>

        <div id="${this._id}-messages" class="flex-1 overflow-y-auto p-3 space-y-2.5 min-h-[400px] max-h-[720px]">
          <div id="${this._id}-loading" class="text-center text-base-content/25 text-xs py-10">
            Loading messages...
          </div>
        </div>

        <div class="px-3 py-2.5 border-t border-base-content/5">
          <div class="flex gap-2">
            <input
              type="text"
              id="${this._id}-input"
              placeholder="${ChatModal.escape(placeholder || '')}"
              class="input input-sm flex-1 bg-base-200/50 border-base-content/8 text-base placeholder:text-base-content/25"
              autocomplete="off"
            />
            <button id="${this._id}-send" class="btn btn-primary btn-sm btn-square">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                <path d="M3.105 2.288a.75.75 0 0 0-.826.95l1.414 4.926A1.5 1.5 0 0 0 5.135 9.25h6.115a.75.75 0 0 1 0 1.5H5.135a1.5 1.5 0 0 0-1.442 1.086l-1.414 4.926a.75.75 0 0 0 .826.95 28.897 28.897 0 0 0 15.293-7.154.75.75 0 0 0 0-1.115A28.897 28.897 0 0 0 3.105 2.289Z" />
              </svg>
            </button>
          </div>
        </div>
      </div>`
  }

  _messageHtml(m) {
    if (m.sender_role === 'error') {
      const closeBtn = this._cfg.errorCloseButton
        ? `<button onclick="document.getElementById('${this._id}')?.remove()" class="text-xs underline mt-1 opacity-70">Close</button>`
        : ''
      return `<div class="flex justify-start">
        <div class="bg-error/10 text-error rounded-xl px-3 py-2 text-sm max-w-[80%]">
          <p>${ChatModal.escape(m.body)}</p>
          ${closeBtn}
        </div>
      </div>`
    }
    const isUser = m.sender_role === 'user'
    return `<div class="flex ${isUser ? 'justify-end' : 'justify-start'}">
      <div class="${isUser ? 'bg-primary/90 text-primary-content rounded-xl rounded-br-sm' : 'bg-base-200/60 rounded-xl rounded-bl-sm'} px-3 py-2 text-sm max-w-[80%] whitespace-pre-wrap">${ChatModal.escape(m.body)}</div>
    </div>`
  }

  _bindEvents(modal) {
    modal.querySelector(`#${this._id}-close`)?.addEventListener('click', () => this._cfg.onClose?.())
    modal.querySelector(`#${this._id}-send`)?.addEventListener('click', () => this._doSend())
    if (this._inputEl) {
      this._inputEl.addEventListener('keydown', e => {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault()
          this._doSend()
        }
      })
    }
  }

  _doSend() {
    if (!this._inputEl || !this._inputEl.value.trim()) return
    const body = this._inputEl.value.trim()
    this._inputEl.value = ''
    this._inputEl.focus()
    this._cfg.onSend?.(body)
  }
}
