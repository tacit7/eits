const MODAL_ID = 'config-guide-chat-modal'
const OPEN_TIMEOUT_MS = 10_000

export const ConfigChatGuide = {
  mounted() {
    this._isOpening = false
    this._sessionUuid = null
    this._messages = []
    this._openTimer = null

    this.el.addEventListener('click', () => this._handleClick())

    this.handleEvent('config_guide_history', ({ messages }) => {
      clearTimeout(this._openTimer)
      this._openTimer = null
      this._isOpening = false
      this._messages = messages || []
      this._renderMessages(this._messages)
    })

    this.handleEvent('config_guide_message', ({ id, body, sender_role, inserted_at }) => {
      if (sender_role === 'user') return
      const msg = { id, body, sender_role, inserted_at }
      this._messages.push(msg)
      this._appendMessage(msg)
    })

    this.handleEvent('config_guide_error', ({ error }) => {
      clearTimeout(this._openTimer)
      this._openTimer = null
      this._isOpening = false
      this._showError(error)
    })
  },

  destroyed() {
    clearTimeout(this._openTimer)
    this._removeModal()
  },

  _handleClick() {
    if (this._isOpening || document.getElementById(MODAL_ID)) return

    this._isOpening = true
    this._setButtonLoading(true)

    fetch('/api/v1/agents', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        instructions: 'Help me configure Claude Code.',
        agent: 'claude-config-guide',
        model: 'sonnet',
      }),
    })
      .then(res => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        return res.json()
      })
      .then(data => {
        this._sessionUuid = data.session_uuid
        this._createModal()
        this.pushEvent('config_guide_open_chat', { session_id: this._sessionUuid })

        this._openTimer = setTimeout(() => {
          this._showError('Config Guide did not respond. Try closing and reopening.')
        }, OPEN_TIMEOUT_MS)
      })
      .catch(err => {
        this._isOpening = false
        this._setButtonLoading(false)
        this._showButtonError(`Failed to start Config Guide: ${err.message}`)
      })
  },

  _createModal() {
    if (document.getElementById(MODAL_ID)) return

    const modal = document.createElement('div')
    modal.id = MODAL_ID
    modal.innerHTML = `
      <div class="fixed bottom-24 right-4 w-[520px] z-[1000] flex flex-col bg-base-100 border border-base-content/10 rounded-xl shadow-2xl max-h-[850px] overflow-hidden">
        <div class="flex items-center justify-between px-4 py-2.5 border-b border-base-content/5 bg-base-200/30">
          <div class="flex items-center gap-2">
            <span class="font-bold text-xs bg-primary/10 text-primary rounded-full w-7 h-7 flex items-center justify-center">CG</span>
            <div>
              <span class="text-xs font-semibold text-base-content/70">Config Guide</span>
            </div>
          </div>
          <button id="config-guide-close" class="btn btn-ghost btn-xs btn-square text-base-content/30" title="Close">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
              <path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z" />
            </svg>
          </button>
        </div>

        <div id="config-guide-messages" class="flex-1 overflow-y-auto p-3 space-y-2.5 min-h-[400px] max-h-[720px]">
          <div id="config-guide-loading" class="text-center text-base-content/25 text-xs py-10">
            Starting Config Guide...
          </div>
        </div>

        <div class="px-3 py-2.5 border-t border-base-content/5">
          <div class="flex gap-2">
            <input
              type="text"
              id="config-guide-input"
              placeholder="Ask about Claude configuration..."
              class="input input-sm flex-1 bg-base-200/50 border-base-content/8 text-sm placeholder:text-base-content/25"
              autocomplete="off"
            />
            <button id="config-guide-send" class="btn btn-primary btn-sm btn-square">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                <path d="M3.105 2.288a.75.75 0 0 0-.826.95l1.414 4.926A1.5 1.5 0 0 0 5.135 9.25h6.115a.75.75 0 0 1 0 1.5H5.135a1.5 1.5 0 0 0-1.442 1.086l-1.414 4.926a.75.75 0 0 0 .826.95 28.897 28.897 0 0 0 15.293-7.154.75.75 0 0 0 0-1.115A28.897 28.897 0 0 0 3.105 2.289Z" />
              </svg>
            </button>
          </div>
        </div>
      </div>`

    document.body.appendChild(modal)

    document.getElementById('config-guide-close')?.addEventListener('click', () => this._close())
    document.getElementById('config-guide-send')?.addEventListener('click', () => this._send())

    const input = document.getElementById('config-guide-input')
    if (input) {
      input.addEventListener('keydown', e => {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault()
          this._send()
        }
      })
    }
  },

  _renderMessages(messages) {
    const container = document.getElementById('config-guide-messages')
    if (!container) return

    if (messages.length === 0) {
      container.innerHTML = `<div class="text-center text-base-content/25 text-xs py-10">No messages yet. Ask anything about Claude configuration.</div>`
    } else {
      container.innerHTML = messages.map(m => this._messageHtml(m)).join('')
    }
    container.scrollTop = container.scrollHeight
    this._setButtonLoading(false)
  },

  _appendMessage(msg) {
    const container = document.getElementById('config-guide-messages')
    if (!container) return

    const loading = document.getElementById('config-guide-loading')
    if (loading) loading.remove()

    const div = document.createElement('div')
    div.innerHTML = this._messageHtml(msg)
    container.appendChild(div.firstChild)
    container.scrollTop = container.scrollHeight
  },

  _messageHtml(m) {
    if (m.sender_role === 'error') {
      return `<div class="flex justify-start">
        <div class="bg-error/10 text-error rounded-xl px-3 py-2 text-sm max-w-[80%]">
          <p>${this._escape(m.body)}</p>
          <button onclick="document.getElementById('${MODAL_ID}')?.remove()" class="text-xs underline mt-1 opacity-70">Close</button>
        </div>
      </div>`
    }
    const isUser = m.sender_role === 'user'
    return `<div class="flex ${isUser ? 'justify-end' : 'justify-start'}">
      <div class="${isUser ? 'bg-primary/90 text-primary-content rounded-xl rounded-br-sm' : 'bg-base-200/60 rounded-xl rounded-bl-sm'} px-3 py-2 text-sm max-w-[80%] whitespace-pre-wrap">${this._escape(m.body)}</div>
    </div>`
  },

  _send() {
    const input = document.getElementById('config-guide-input')
    if (!input || !input.value.trim() || !this._sessionUuid) return

    const body = input.value.trim()
    input.value = ''
    input.focus()

    const msg = { body, sender_role: 'user' }
    this._messages.push(msg)
    this._appendMessage(msg)

    this.pushEvent('config_guide_send_message', {
      session_id: this._sessionUuid,
      body,
    })
  },

  _close() {
    this._removeModal()
    this.pushEvent('config_guide_close_chat', {})
    this._sessionUuid = null
    this._messages = []
    this._isOpening = false
    clearTimeout(this._openTimer)
    this._openTimer = null
    this._setButtonLoading(false)
  },

  _removeModal() {
    document.getElementById(MODAL_ID)?.remove()
  },

  _showError(message) {
    const container = document.getElementById('config-guide-messages')
    if (container) {
      this._appendMessage({ body: message, sender_role: 'error' })
    }
    this._setButtonLoading(false)
    this._isOpening = false
  },

  _showButtonError(message) {
    const existing = document.getElementById('config-guide-btn-error')
    if (existing) existing.remove()

    const el = document.createElement('span')
    el.id = 'config-guide-btn-error'
    el.className = 'text-error text-xs ml-2'
    el.textContent = message
    this.el.insertAdjacentElement('afterend', el)
    setTimeout(() => el.remove(), 4000)
  },

  _setButtonLoading(loading) {
    this.el.disabled = loading
    const existing = this.el.querySelector('.loading-spinner')
    if (loading && !existing) {
      this.el.insertAdjacentHTML('afterbegin', '<span class="loading loading-spinner loading-xs mr-1"></span>')
    } else if (!loading && existing) {
      existing.remove()
    }
  },

  _escape(str) {
    const div = document.createElement('div')
    div.textContent = str
    return div.innerHTML
  },
}
