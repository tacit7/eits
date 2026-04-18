import { FloatingChatModal } from './floating_chat_modal.js'

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

export const FloatingChat = {
  mounted() {
    this._chatAgent = null
    this._chatMessages = []
    this._unreadCount = 0
    this._expanded = false
    this._modal = null

    // Push bookmarks to server so the LiveComponent can render them
    this._syncBookmarks()

    this._onBookmarksUpdated = () => this._syncBookmarks()
    window.addEventListener('bookmarks-updated', this._onBookmarksUpdated)

    this.handleEvent('fab_chat_history', ({ messages }) => {
      this._chatMessages = messages || []
      this._modal?.setMessages(this._chatMessages, 'No messages yet')
    })

    this.handleEvent('fab_chat_message', ({ body, sender_role }) => {
      const msg = { body, sender_role, ts: new Date().toISOString() }
      this._chatMessages.push(msg)
      this._modal?.appendMessage(msg)
      if (!this._chatAgent) {
        this._unreadCount++
        this._updateUnreadBadge()
      }
    })

    this.handleEvent('fab_chat_error', ({ error }) => {
      const msg = { body: error, sender_role: 'error', ts: new Date().toISOString() }
      this._chatMessages.push(msg)
      this._modal?.appendMessage(msg)
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

    this._modal?.destroy()
    const statusLabel = agent.status || 'idle'
    const isActive = ['working', 'compacting'].includes(statusLabel)
    this._modal = new FloatingChatModal({
      id: 'fab-chat-modal',
      title: agent.name || 'Agent',
      initials: this._initials(agent.name),
      subtitle: statusLabel,
      subtitleClass: isActive ? 'text-success' : 'text-base-content/30',
      placeholder: `Message ${agent.name || 'agent'}...`,
      dmHref: `/dm/${agent.session_id}`,
      onSend: (body) => this._onSend(body),
      onClose: () => this._closeChat(),
    }).create()

    this.pushEvent('fab_open_chat', { session_id: agent.session_id })
    this._modal.focusInput()
  },

  _closeChat(notify = true) {
    this._chatAgent = null
    this._chatMessages = []
    this._modal?.destroy()
    this._modal = null
    if (notify) this.pushEvent('fab_close_chat', {})
  },

  _onSend(body) {
    if (!this._chatAgent) return
    const msg = { body, sender_role: 'user', ts: new Date().toISOString() }
    this._chatMessages.push(msg)
    this._modal?.appendMessage(msg)
    this.pushEvent('fab_send_message', {
      session_id: this._chatAgent.session_id,
      body,
    })
  },

  _initials(name) {
    if (!name) return '?'
    return name.split(' ').map(w => w[0]).join('').substring(0, 2).toUpperCase()
  },
}
