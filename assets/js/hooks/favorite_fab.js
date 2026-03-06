const STORAGE_KEY = 'eye-in-the-sky-bookmarks'

const STATUS_STYLES = {
  working:   { dot: 'bg-success',          ping: true  },
  compacting:{ dot: 'bg-warning',          ping: true  },
  idle:      { dot: 'bg-base-content/20',  ping: false },
  completed: { dot: 'bg-base-content/20',  ping: false },
  default:   { dot: 'bg-base-content/20',  ping: false },
}

export const FavoriteFab = {
  mounted() {
    this._statuses = {}
    this._chatAgent = null
    this._chatMessages = []
    this._render()

    this._onBookmarksUpdated = () => this._render()
    window.addEventListener('bookmarks-updated', this._onBookmarksUpdated)

    this.handleEvent('fab_status_update', ({ statuses }) => {
      this._statuses = statuses || {}
      this._render()
    })

    this.handleEvent('fab_chat_message', ({ body, sender_role }) => {
      this._chatMessages.push({ body, sender_role, ts: new Date().toISOString() })
      this._renderChat()
    })

    this.handleEvent('fab_chat_error', ({ error }) => {
      this._chatMessages.push({ body: error, sender_role: 'error', ts: new Date().toISOString() })
      this._renderChat()
    })

    this.pushEvent('fab_request_statuses', {})
  },

  destroyed() {
    window.removeEventListener('bookmarks-updated', this._onBookmarksUpdated)
  },

  _getBookmarks() {
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      return stored ? JSON.parse(stored) : []
    } catch (e) {
      return []
    }
  },

  _getStatusStyle(sessionId, fallbackStatus) {
    const status = this._statuses[sessionId] || fallbackStatus || 'idle'
    return STATUS_STYLES[status] || STATUS_STYLES.default
  },

  _getInitials(name) {
    if (!name) return '?'
    return name.split(' ').map(w => w[0]).join('').substring(0, 2).toUpperCase()
  },

  _removeBookmark(index) {
    const bookmarks = this._getBookmarks()
    if (!bookmarks[index]) return
    bookmarks.splice(index, 1)
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(bookmarks))
    } catch (e) { /* ignore */ }
    window.dispatchEvent(new CustomEvent('bookmarks-updated', {
      detail: { bookmarks }
    }))
    this._render()
  },

  _openChat(agent) {
    this._chatAgent = agent
    this._chatMessages = []
    this._renderChat()
  },

  _closeChat() {
    this._chatAgent = null
    this._chatMessages = []
    const modal = document.getElementById('fab-chat-modal')
    if (modal) modal.remove()
  },

  _sendMessage() {
    const input = document.getElementById('fab-chat-input')
    if (!input || !input.value.trim() || !this._chatAgent) return

    const body = input.value.trim()
    this._chatMessages.push({ body, sender_role: 'user', ts: new Date().toISOString() })
    this._renderChat()

    this.pushEvent('fab_send_message', {
      session_id: this._chatAgent.session_id,
      body: body
    })

    input.value = ''
    input.focus()
  },

  _renderChat() {
    let modal = document.getElementById('fab-chat-modal')
    if (!this._chatAgent) {
      if (modal) modal.remove()
      return
    }

    const agent = this._chatAgent
    const style = this._getStatusStyle(agent.session_id, agent.status)
    const statusLabel = this._statuses[agent.session_id] || agent.status || 'idle'

    const messagesHtml = this._chatMessages.length === 0
      ? `<div class="text-center text-base-content/25 text-xs py-10">
           Send a message to ${(agent.name || 'Agent').replace(/</g, '&lt;')}
         </div>`
      : this._chatMessages.map(m => {
          if (m.sender_role === 'error') {
            return `<div class="flex justify-start">
              <div class="bg-error/10 text-error rounded-xl px-3 py-2 text-sm max-w-[80%]">${this._escapeHtml(m.body)}</div>
            </div>`
          }
          const isUser = m.sender_role === 'user'
          return `<div class="flex ${isUser ? 'justify-end' : 'justify-start'}">
            <div class="${isUser ? 'bg-primary/90 text-primary-content rounded-xl rounded-br-sm' : 'bg-base-200/60 rounded-xl rounded-bl-sm'} px-3 py-2 text-sm max-w-[80%] whitespace-pre-wrap">${this._escapeHtml(m.body)}</div>
          </div>`
        }).join('')

    const html = `
      <div class="fixed bottom-4 right-4 w-96 z-[1000] flex flex-col bg-base-100 border border-base-content/10 rounded-xl shadow-2xl max-h-[500px] overflow-hidden">
        <div class="flex items-center justify-between px-4 py-2.5 border-b border-base-content/5 bg-base-200/30">
          <div class="flex items-center gap-2">
            <span class="font-bold text-xs bg-primary/10 text-primary rounded-full w-7 h-7 flex items-center justify-center">${this._getInitials(agent.name)}</span>
            <div>
              <span class="text-xs font-semibold text-base-content/70">${this._escapeHtml(agent.name || 'Agent')}</span>
              <span class="text-[10px] font-medium uppercase tracking-wider ml-1.5 ${style.ping ? 'text-success' : 'text-base-content/30'}">${statusLabel}</span>
            </div>
          </div>
          <div class="flex items-center gap-1">
            <a href="/dm/${agent.session_id}" class="btn btn-ghost btn-xs btn-square text-base-content/30 hover:text-primary" title="Open full DM">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                <path fill-rule="evenodd" d="M4.25 5.5a.75.75 0 0 0-.75.75v8.5c0 .414.336.75.75.75h8.5a.75.75 0 0 0 .75-.75v-4a.75.75 0 0 1 1.5 0v4A2.25 2.25 0 0 1 12.75 17h-8.5A2.25 2.25 0 0 1 2 14.75v-8.5A2.25 2.25 0 0 1 4.25 4h5a.75.75 0 0 1 0 1.5h-5Z" clip-rule="evenodd" />
                <path fill-rule="evenodd" d="M6.194 12.753a.75.75 0 0 0 1.06.053L16.5 4.44v2.81a.75.75 0 0 0 1.5 0v-4.5a.75.75 0 0 0-.75-.75h-4.5a.75.75 0 0 0 0 1.5h2.553l-9.056 8.194a.75.75 0 0 0-.053 1.06Z" clip-rule="evenodd" />
              </svg>
            </a>
            <button id="fab-chat-close" class="btn btn-ghost btn-xs btn-square text-base-content/30" title="Close">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                <path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z" />
              </svg>
            </button>
          </div>
        </div>

        <div id="fab-chat-messages" class="flex-1 overflow-y-auto p-3 space-y-2.5 min-h-[200px] max-h-[360px]">
          ${messagesHtml}
        </div>

        <div class="px-3 py-2.5 border-t border-base-content/5">
          <div class="flex gap-2">
            <input
              type="text"
              id="fab-chat-input"
              placeholder="Message ${this._escapeHtml(agent.name || 'agent')}..."
              class="input input-sm flex-1 bg-base-200/50 border-base-content/8 text-sm placeholder:text-base-content/25"
              autocomplete="off"
            />
            <button id="fab-chat-send" class="btn btn-primary btn-sm btn-square">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                <path d="M3.105 2.288a.75.75 0 0 0-.826.95l1.414 4.926A1.5 1.5 0 0 0 5.135 9.25h6.115a.75.75 0 0 1 0 1.5H5.135a1.5 1.5 0 0 0-1.442 1.086l-1.414 4.926a.75.75 0 0 0 .826.95 28.897 28.897 0 0 0 15.293-7.154.75.75 0 0 0 0-1.115A28.897 28.897 0 0 0 3.105 2.289Z" />
              </svg>
            </button>
          </div>
        </div>
      </div>`

    if (!modal) {
      modal = document.createElement('div')
      modal.id = 'fab-chat-modal'
      document.body.appendChild(modal)
    }
    modal.innerHTML = html

    // Scroll messages to bottom
    const msgContainer = document.getElementById('fab-chat-messages')
    if (msgContainer) msgContainer.scrollTop = msgContainer.scrollHeight

    // Wire up events
    document.getElementById('fab-chat-close')?.addEventListener('click', () => this._closeChat())
    document.getElementById('fab-chat-send')?.addEventListener('click', () => this._sendMessage())
    const input = document.getElementById('fab-chat-input')
    if (input) {
      input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault()
          this._sendMessage()
        }
      })
      input.focus()
    }
  },

  _escapeHtml(str) {
    const div = document.createElement('div')
    div.textContent = str
    return div.innerHTML
  },

  _render() {
    const bookmarks = this._getBookmarks()
    this._agentMap = bookmarks

    if (bookmarks.length === 0) {
      this.el.innerHTML = ''
      this.el.classList.add('hidden')
      return
    }

    this.el.classList.remove('hidden')

    const mainBtn = `
      <div tabindex="0" role="button"
           class="btn btn-primary btn-circle shadow-lg outline-none">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6">
          <path fill-rule="evenodd" d="M7.5 6a4.5 4.5 0 1 1 9 0 4.5 4.5 0 0 1-9 0ZM3.751 20.105a8.25 8.25 0 0 1 16.498 0 .75.75 0 0 1-.437.695A18.683 18.683 0 0 1 12 22.5c-2.786 0-5.433-.608-7.812-1.7a.75.75 0 0 1-.437-.695Z" clip-rule="evenodd" />
        </svg>
        <span class="badge badge-sm badge-warning absolute -top-1 -right-1">${bookmarks.length}</span>
      </div>`

    const closeBtn = `
      <button class="btn btn-circle btn-ghost fab-close" tabindex="0">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5">
          <path fill-rule="evenodd" d="M5.47 5.47a.75.75 0 0 1 1.06 0L12 10.94l5.47-5.47a.75.75 0 1 1 1.06 1.06L13.06 12l5.47 5.47a.75.75 0 1 1-1.06 1.06L12 13.06l-5.47 5.47a.75.75 0 0 1-1.06-1.06L10.94 12 5.47 6.53a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
        </svg>
      </button>`

    const agentBtns = bookmarks.map((agent, index) => {
      const style = this._getStatusStyle(agent.session_id, agent.status)
      const initials = this._getInitials(agent.name)
      const statusDot = style.ping
        ? `<span class="absolute -bottom-0.5 -right-0.5 flex h-3 w-3">
             <span class="animate-ping absolute inline-flex h-full w-full rounded-full ${style.dot} opacity-50"></span>
             <span class="relative inline-flex rounded-full h-3 w-3 ${style.dot} ring-2 ring-base-100"></span>
           </span>`
        : `<span class="absolute -bottom-0.5 -right-0.5 inline-flex rounded-full h-3 w-3 ${style.dot} ring-2 ring-base-100"></span>`

      return `
        <button
           class="btn btn-circle bg-base-100 shadow-md hover:bg-base-200 border border-base-content/10 relative group fab-agent-btn"
           title="${(agent.name || 'Agent').replace(/"/g, '&quot;')}"
           data-agent-index="${index}">
          <span class="font-bold text-xs text-base-content/70">${initials}</span>
          ${statusDot}
          <span class="fab-remove-btn absolute -top-1 -right-1 w-4 h-4 rounded-full bg-error text-error-content flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer z-10 shadow-sm"
                data-remove-index="${index}">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="w-2.5 h-2.5">
              <path d="M5.28 4.22a.75.75 0 0 0-1.06 1.06L6.94 8l-2.72 2.72a.75.75 0 1 0 1.06 1.06L8 9.06l2.72 2.72a.75.75 0 1 0 1.06-1.06L9.06 8l2.72-2.72a.75.75 0 0 0-1.06-1.06L8 6.94 5.28 4.22Z" />
            </svg>
          </span>
          <span class="absolute -top-8 left-1/2 -translate-x-1/2 px-2 py-1 bg-base-300 text-base-content text-xs rounded shadow-lg whitespace-nowrap opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none">
            ${(agent.name || 'Agent').replace(/</g, '&lt;')}
          </span>
        </button>`
    }).join('')

    this.el.innerHTML = mainBtn + closeBtn + agentBtns

    // Wire up remove buttons (stop propagation so chat doesn't open)
    this.el.querySelectorAll('.fab-remove-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.preventDefault()
        e.stopPropagation()
        const idx = parseInt(btn.dataset.removeIndex, 10)
        this._removeBookmark(idx)
      })
    })

    // Wire up agent button clicks to open chat
    this.el.querySelectorAll('.fab-agent-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.preventDefault()
        e.stopPropagation()
        const idx = parseInt(btn.dataset.agentIndex, 10)
        const agent = this._agentMap[idx]
        if (agent) this._openChat(agent)
      })
    })
  }
}
