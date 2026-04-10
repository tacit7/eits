const STORAGE_KEY = 'eye-in-the-sky-bookmarks'
const FAB_RADIUS = 90  // px — radial distance from main button to agent buttons

// Compute radial offsets for N buttons, arc from 90° (up) to 180° (left)
function radialOffsets(n) {
  if (n === 0) return []
  const angles = n === 1
    ? [135]
    : Array.from({ length: n }, (_, i) => 90 + i * 90 / (n - 1))
  return angles.map(deg => {
    const rad = deg * Math.PI / 180
    return {
      x: Math.round(FAB_RADIUS * Math.cos(rad)),
      y: Math.round(-FAB_RADIUS * Math.sin(rad)),
    }
  })
}

export const FavoriteFab = {
  mounted() {
    this._chatAgent = null
    this._chatMessages = []
    this._unreadCount = 0
    this._expanded = false

    // Push bookmarks to server so the LiveComponent can render them
    this._syncBookmarks()

    this._onBookmarksUpdated = () => this._syncBookmarks()
    window.addEventListener('bookmarks-updated', this._onBookmarksUpdated)

    this.handleEvent('fab_chat_history', ({ messages }) => {
      this._chatMessages = messages || []
      this._refreshMessages()
    })

    this.handleEvent('fab_chat_message', ({ body, sender_role }) => {
      const msg = { body, sender_role, ts: new Date().toISOString() }
      this._chatMessages.push(msg)
      this._appendMessage(msg)
      if (!this._chatAgent) {
        this._unreadCount++
        this._updateUnreadBadge()
      }
    })

    this.handleEvent('fab_chat_error', ({ error }) => {
      const msg = { body: error, sender_role: 'error', ts: new Date().toISOString() }
      this._chatMessages.push(msg)
      this._appendMessage(msg)
    })

    this.handleEvent('open_fab_chat', (detail) => {
      this._openChat(detail)
    })

    // Event delegation — survives server-side re-renders
    this.el.addEventListener('click', (e) => this._handleClick(e))

    this._applyRadialOffsets()
  },

  updated() {
    // Called after the LiveComponent re-renders (e.g. status update or new bookmarks).
    // Re-apply positions and restore expand state.
    this._applyRadialOffsets()
    if (this._expanded) this._setExpanded(true)
    this._updateUnreadBadge()
  },

  destroyed() {
    window.removeEventListener('bookmarks-updated', this._onBookmarksUpdated)
  },

  // --- bookmark sync ---

  _syncBookmarks() {
    const bookmarks = this._getBookmarks()
    this.pushEvent('fab_set_bookmarks', { bookmarks })
  },

  _getBookmarks() {
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      return stored ? JSON.parse(stored) : []
    } catch (e) {
      return []
    }
  },

  _removeBookmark(index) {
    const bookmarks = this._getBookmarks()
    if (!bookmarks[index]) return
    bookmarks.splice(index, 1)
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(bookmarks))
    } catch (e) { /* ignore */ }
    window.dispatchEvent(new CustomEvent('bookmarks-updated', { detail: { bookmarks } }))
  },

  // --- click handling (delegated) ---

  _handleClick(e) {
    const removeBtn = e.target.closest('.fab-remove-btn')
    const agentBtn = e.target.closest('.fab-agent-btn')
    const mainBtn = e.target.closest('[role="button"]')

    if (removeBtn) {
      e.preventDefault()
      e.stopPropagation()
      this._removeBookmark(parseInt(removeBtn.dataset.removeIndex, 10))
    } else if (agentBtn) {
      e.stopPropagation()
      if (window.innerWidth >= 640) {
        e.preventDefault()
        const agent = {
          session_id: agentBtn.dataset.sessionId,
          name: agentBtn.dataset.agentName,
          status: agentBtn.dataset.agentStatus,
        }
        this._openChat(agent)
      }
      // mobile: let <a href> navigate naturally
    } else if (mainBtn) {
      e.stopPropagation()
      this._setExpanded(!this._expanded)
    }
  },

  // --- radial layout ---

  _applyRadialOffsets() {
    const agentEls = Array.from(this.el.querySelectorAll('.fab-agent-btn'))
    const offsets = radialOffsets(agentEls.length)
    agentEls.forEach((el, i) => {
      el._tx = offsets[i].x
      el._ty = offsets[i].y
    })
  },

  _setExpanded(val) {
    this._expanded = val
    this.el.querySelectorAll('.fab-agent-btn').forEach(el => {
      if (val) {
        el.style.opacity = '1'
        el.style.pointerEvents = 'auto'
        el.style.transform = `translate(${el._tx}px, ${el._ty}px) scale(1)`
      } else {
        el.style.opacity = '0'
        el.style.pointerEvents = 'none'
        el.style.transform = 'translate(0,0) scale(0.5)'
      }
    })
  },

  // --- unread badge (DOM-applied on top of server-rendered main button) ---

  _updateUnreadBadge() {
    const mainBtn = this.el.querySelector('[role="button"]')
    if (!mainBtn) return
    const existing = mainBtn.querySelector('span.absolute')
    if (existing) existing.remove()
    if (this._unreadCount > 0) {
      mainBtn.insertAdjacentHTML('beforeend',
        `<span class="absolute -top-1 -right-1 flex h-3 w-3">
           <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-error opacity-75"></span>
           <span class="relative inline-flex rounded-full h-3 w-3 bg-error ring-2 ring-base-100"></span>
         </span>`)
    }
  },

  // --- chat modal (client-side only, no server involvement for layout) ---

  _openChat(agent) {
    if (this._chatAgent && this._chatAgent.session_id !== agent.session_id) {
      this.pushEvent('fab_close_chat', {})
    }
    this._chatAgent = agent
    this._chatMessages = []
    this._unreadCount = 0
    this._updateUnreadBadge()
    this._createChatModal()
    this.pushEvent('fab_open_chat', { session_id: agent.session_id })
    document.getElementById('fab-chat-input')?.focus()
  },

  _closeChat(notify = true) {
    this._chatAgent = null
    this._chatMessages = []
    const modal = document.getElementById('fab-chat-modal')
    if (modal) modal.remove()
    if (notify) this.pushEvent('fab_close_chat', {})
  },

  _sendMessage() {
    const input = document.getElementById('fab-chat-input')
    if (!input || !input.value.trim() || !this._chatAgent) return

    const body = input.value.trim()
    const msg = { body, sender_role: 'user', ts: new Date().toISOString() }
    this._chatMessages.push(msg)
    this._appendMessage(msg)

    this.pushEvent('fab_send_message', {
      session_id: this._chatAgent.session_id,
      body
    })

    input.value = ''
    input.focus()
  },

  _createChatModal() {
    const existing = document.getElementById('fab-chat-modal')
    if (existing) existing.remove()

    const agent = this._chatAgent
    const statusLabel = agent.status || 'idle'
    const isActive = ['working', 'compacting'].includes(statusLabel)

    const modal = document.createElement('div')
    modal.id = 'fab-chat-modal'
    modal.innerHTML = `
      <div class="fixed bottom-24 right-4 w-[520px] z-[1000] flex flex-col bg-base-100 border border-base-content/10 rounded-xl shadow-2xl max-h-[850px] overflow-hidden">
        <div class="flex items-center justify-between px-4 py-2.5 border-b border-base-content/5 bg-base-200/30">
          <div class="flex items-center gap-2">
            <span class="font-bold text-xs bg-primary/10 text-primary rounded-full w-7 h-7 flex items-center justify-center">${this._initials(agent.name)}</span>
            <div>
              <span class="text-xs font-semibold text-base-content/70">${this._escapeHtml(agent.name || 'Agent')}</span>
              <span id="fab-chat-status" class="text-[10px] font-medium uppercase tracking-wider ml-1.5 ${isActive ? 'text-success' : 'text-base-content/30'}">${statusLabel}</span>
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

        <div id="fab-chat-messages" class="flex-1 overflow-y-auto p-3 space-y-2.5 min-h-[400px] max-h-[720px]">
          <div id="fab-chat-empty" class="text-center text-base-content/25 text-xs py-10">
            Loading messages...
          </div>
        </div>

        <div class="px-3 py-2.5 border-t border-base-content/5">
          <div class="flex gap-2">
            <input
              type="text"
              id="fab-chat-input"
              placeholder="Message ${this._escapeHtml(agent.name || 'agent')}..."
              class="input input-sm flex-1 bg-base-200/50 border-base-content/8 text-base placeholder:text-base-content/25"
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

    document.body.appendChild(modal)

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
    }
  },

  _refreshMessages() {
    const container = document.getElementById('fab-chat-messages')
    if (!container) return
    if (this._chatMessages.length === 0) {
      container.innerHTML = `<div id="fab-chat-empty" class="text-center text-base-content/25 text-xs py-10">No messages yet</div>`
    } else {
      container.innerHTML = this._chatMessages.map(m => this._messageHtml(m)).join('')
    }
    container.scrollTop = container.scrollHeight
  },

  _appendMessage(msg) {
    const container = document.getElementById('fab-chat-messages')
    if (!container) return
    const empty = document.getElementById('fab-chat-empty')
    if (empty) empty.remove()
    const div = document.createElement('div')
    div.innerHTML = this._messageHtml(msg)
    container.appendChild(div.firstChild)
    container.scrollTop = container.scrollHeight
  },

  _messageHtml(m) {
    if (m.sender_role === 'error') {
      return `<div class="flex justify-start">
        <div class="bg-error/10 text-error rounded-xl px-3 py-2 text-sm max-w-[80%]">${this._escapeHtml(m.body)}</div>
      </div>`
    }
    const isUser = m.sender_role === 'user'
    return `<div class="flex ${isUser ? 'justify-end' : 'justify-start'}">
      <div class="${isUser ? 'bg-primary/90 text-primary-content rounded-xl rounded-br-sm' : 'bg-base-200/60 rounded-xl rounded-bl-sm'} px-3 py-2 text-sm max-w-[80%] whitespace-pre-wrap">${this._escapeHtml(m.body)}</div>
    </div>`
  },

  _initials(name) {
    if (!name) return '?'
    return name.split(' ').map(w => w[0]).join('').substring(0, 2).toUpperCase()
  },

  _escapeHtml(str) {
    const div = document.createElement('div')
    div.textContent = str
    return div.innerHTML
  },
}
