import { FloatingChatModal } from './floating_chat_modal.js'

const MODAL_ID = 'config-guide-chat-modal'
const OPEN_TIMEOUT_MS = 10_000

export const ConfigChatGuide = {
  mounted() {
    this._isOpening = false
    this._sessionUuid = null
    this._messages = []
    this._openTimer = null
    this._modal = null

    this.el.addEventListener('click', () => this._handleClick())

    this.handleEvent('config_guide_agent_started', ({ session_uuid }) => {
      this._isOpening = false
      this._sessionUuid = session_uuid
      this._modal = new FloatingChatModal({
        id: MODAL_ID,
        title: 'Config Guide',
        initials: 'CG',
        placeholder: 'Ask about Claude configuration...',
        errorCloseButton: true,
        onSend: (body) => this._onSend(body),
        onClose: () => this._close(),
      }).create()
      this.pushEvent('config_guide_open_chat', { session_id: this._sessionUuid })

      this._openTimer = setTimeout(() => {
        this._showError('Config Guide did not respond. Try closing and reopening.')
      }, OPEN_TIMEOUT_MS)
    })

    this.handleEvent('config_guide_history', ({ messages }) => {
      clearTimeout(this._openTimer)
      this._openTimer = null
      this._isOpening = false
      this._messages = messages || []
      this._modal?.setMessages(this._messages, 'No messages yet. Ask anything about Claude configuration.')
      this._setButtonLoading(false)
    })

    this.handleEvent('config_guide_message', ({ id, body, sender_role, inserted_at }) => {
      if (sender_role === 'user') return
      const msg = { id, body, sender_role, inserted_at }
      this._messages.push(msg)
      this._modal?.appendMessage(msg)
    })

    this.handleEvent('config_guide_error', ({ error }) => {
      clearTimeout(this._openTimer)
      this._openTimer = null
      this._isOpening = false
      this._setButtonLoading(false)
      this._showError(error)
    })
  },

  destroyed() {
    clearTimeout(this._openTimer)
    this._modal?.destroy()
    this._modal = null
  },

  _handleClick() {
    if (this._isOpening || this._modal?.exists()) return

    this._isOpening = true
    this._setButtonLoading(true)
    this.pushEvent('start_config_guide_agent', {})
  },

  _onSend(body) {
    if (!this._sessionUuid) return
    const msg = { body, sender_role: 'user' }
    this._messages.push(msg)
    this._modal?.appendMessage(msg)
    this.pushEvent('config_guide_send_message', {
      session_id: this._sessionUuid,
      body,
    })
  },

  _close() {
    this._modal?.destroy()
    this._modal = null
    this.pushEvent('config_guide_close_chat', {})
    this._sessionUuid = null
    this._messages = []
    this._isOpening = false
    clearTimeout(this._openTimer)
    this._openTimer = null
    this._setButtonLoading(false)
  },

  _showError(message) {
    if (this._modal?.exists()) {
      this._modal.appendMessage({ body: message, sender_role: 'error' })
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

}
