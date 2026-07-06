// CtxMenu — one web-rendered context menu for browser AND desktop webview.
//
// Mounts once on #ctx-menu-root in the app layout (a real in-layout element,
// NOT the root layout — phx-hook on root layout elements is silently ignored).
// A delegated `contextmenu` listener opens the menu on the nearest [data-ctx]
// ancestor; right-click anywhere else keeps the default browser/webview menu.
//
// Item lists come from context_menu_registry.js. LiveView actions dispatch
// `ctx-action` CustomEvents which this hook forwards via pushEventTo to the
// Rail LiveComponent for session actions (same handlers the legacy native
// menu used) and to the page LiveView for everything else.

import { itemsFor, clampPosition } from '../context_menu_registry'

const LONG_PRESS_MS = 500

export const CtxMenu = {
  mounted() {
    this._menuEl = null
    this._items = []
    this._focusIdx = -1
    this._subEl = null
    this._trigger = null

    // --- open: right-click ---------------------------------------------------
    this._onContextMenu = (e) => {
      const target = e.target.closest('[data-ctx]')
      if (!target) return
      const items = itemsFor(target.dataset.ctx, target.dataset, this._isTauri())
      if (!items) return
      e.preventDefault()
      e.stopPropagation()
      this._open(items, e.clientX, e.clientY, target)
    }
    document.addEventListener('contextmenu', this._onContextMenu)

    // --- open: long-press (touch) --------------------------------------------
    this._lpTimer = null
    this._onTouchStart = (e) => {
      const target = e.target.closest('[data-ctx]')
      if (!target || e.touches.length !== 1) return
      const { clientX, clientY } = e.touches[0]
      this._lpTimer = setTimeout(() => {
        const items = itemsFor(target.dataset.ctx, target.dataset, this._isTauri())
        if (items) this._open(items, clientX, clientY, target)
      }, LONG_PRESS_MS)
    }
    this._cancelLp = () => clearTimeout(this._lpTimer)
    document.addEventListener('touchstart', this._onTouchStart, { passive: true })
    document.addEventListener('touchmove', this._cancelLp, { passive: true })
    document.addEventListener('touchend', this._cancelLp, { passive: true })

    // --- dismiss --------------------------------------------------------------
    this._onDismiss = (e) => {
      if (this._menuEl && !this._menuEl.contains(e.target)) this._close()
    }
    this._onScroll = () => this._close()
    this._onKeydown = (e) => this._keyboard(e)
    document.addEventListener('mousedown', this._onDismiss)
    document.addEventListener('scroll', this._onScroll, true)
    document.addEventListener('keydown', this._onKeydown, true)
  },

  destroyed() {
    this._close()
    document.removeEventListener('contextmenu', this._onContextMenu)
    document.removeEventListener('touchstart', this._onTouchStart)
    document.removeEventListener('touchmove', this._cancelLp)
    document.removeEventListener('touchend', this._cancelLp)
    document.removeEventListener('mousedown', this._onDismiss)
    document.removeEventListener('scroll', this._onScroll, true)
    document.removeEventListener('keydown', this._onKeydown, true)
  },

  // --- action context passed to registry run() -------------------------------
  _ctx() {
    const hook = this
    return {
      navigate(path) {
        hook._close()
        window.liveSocket.pushHistoryPatch // presence check only
        // Full live navigation regardless of current view:
        window.liveSocket.historyRedirect
          ? window.liveSocket.historyRedirect(path, 'push', null)
          : (window.location.href = path)
      },
      invoke(cmd, args) {
        hook._close()
        if (window.__TAURI_INTERNALS__) {
          window.__TAURI_INTERNALS__.invoke(cmd, args ?? {}).catch(() => {})
        }
      },
      copy(text) {
        hook._close()
        if (window.__TAURI_INTERNALS__) {
          window.__TAURI_INTERNALS__
            .invoke('plugin:clipboard-manager|write_text', { text })
            .catch(() => navigator.clipboard?.writeText(text))
        } else {
          navigator.clipboard?.writeText(text)
        }
        this.flash('Copied')
      },
      push(event, payload) {
        hook._close()
        // Session actions reuse the Rail LC handlers (archive_session /
        // rename_session / open_worktree) — same protocol as the retired
        // native menu. Everything else goes to the page LiveView.
        const railEvents = ['archive_session', 'rename_session', 'open_worktree']
        if (railEvents.includes(event)) {
          // extra spreads AFTER the stringified session_id in the bridge —
          // never default it to the whole payload or its integer session_id
          // clobbers the string one and Integer.parse/1 raises server-side.
          window.dispatchEvent(
            new CustomEvent('tauri:session-action', {
              detail: { action: event, session_id: payload.session_id, extra: payload.extra ?? {} },
            })
          )
        } else {
          hook.pushEvent(event, payload)
        }
      },
      flash(msg) {
        hook._close()
        window.dispatchEvent(
          new CustomEvent('phx:flash', { detail: { kind: 'info', msg } })
        )
      },
    }
  },

  _isTauri() {
    return document.documentElement.getAttribute('data-env') === 'tauri'
  },

  // --- rendering --------------------------------------------------------------
  _open(items, x, y, trigger) {
    this._close()
    this._items = items
    this._trigger = trigger
    this._focusIdx = -1

    const menu = this._buildList(items, false)
    menu.style.visibility = 'hidden'
    document.body.appendChild(menu)
    const { width, height } = menu.getBoundingClientRect()
    const { left, top } = clampPosition(x, y, width, height, window.innerWidth, window.innerHeight)
    menu.style.left = `${left}px`
    menu.style.top = `${top}px`
    menu.style.visibility = ''
    this._menuEl = menu
  },

  _buildList(items, isSub) {
    const menu = document.createElement('div')
    menu.className = 'ctx-menu' + (isSub ? ' ctx-menu-sub' : '')
    menu.setAttribute('role', 'menu')
    items.forEach((item, i) => {
      if (item.sep) {
        const sep = document.createElement('div')
        sep.className = 'ctx-menu-sep'
        sep.setAttribute('role', 'separator')
        menu.appendChild(sep)
        return
      }
      const el = document.createElement('button')
      el.type = 'button'
      el.className = 'ctx-menu-item' + (item.danger ? ' ctx-menu-danger' : '')
      el.setAttribute('role', 'menuitem')
      el.dataset.idx = String(i)
      const iconHtml = item.dot
        ? `<span class="ctx-menu-dot" style="background:${item.dot}"></span>`
        : `<span class="ctx-menu-ic">${item.icon || ''}</span>`
      el.innerHTML = `${iconHtml}<span class="ctx-menu-label"></span>${item.children ? '<span class="ctx-menu-sub-arrow">▸</span>' : ''}`
      el.querySelector('.ctx-menu-label').textContent = item.label
      if (item.children) {
        el.addEventListener('mouseenter', () => this._openSub(el, item))
        el.addEventListener('click', () => this._openSub(el, item))
      } else {
        el.addEventListener('mouseenter', () => {
          if (!isSub) this._closeSub()
        })
        el.addEventListener('click', () => this._activate(item, el))
      }
      menu.appendChild(el)
    })
    return menu
  },

  _openSub(anchorEl, item) {
    this._closeSub()
    const sub = this._buildList(item.children, true)
    sub.style.visibility = 'hidden'
    document.body.appendChild(sub)
    const a = anchorEl.getBoundingClientRect()
    const { width, height } = sub.getBoundingClientRect()
    let left = a.right + 2
    if (left + width > window.innerWidth) left = a.left - width - 2
    let top = Math.min(a.top - 5, window.innerHeight - height - 4)
    sub.style.left = `${left}px`
    sub.style.top = `${Math.max(4, top)}px`
    sub.style.visibility = ''
    this._subEl = sub
  },

  _activate(item, el) {
    if (item.danger && !el.dataset.confirming) {
      // inline confirm: the row becomes "Really? ✓ / ✕"
      el.dataset.confirming = '1'
      el.innerHTML =
        '<span class="ctx-menu-ic">⚠</span><span class="ctx-menu-label">Really?</span>' +
        '<span class="ctx-menu-confirm"><span data-yes>✓</span><span data-no>✕</span></span>'
      el.querySelector('[data-yes]').addEventListener('click', (e) => {
        e.stopPropagation()
        item.run(this._ctx())
      })
      el.querySelector('[data-no]').addEventListener('click', (e) => {
        e.stopPropagation()
        this._close()
      })
      return
    }
    item.run(this._ctx())
  },

  // --- keyboard ----------------------------------------------------------------
  _keyboard(e) {
    if (!this._menuEl) return
    const focusables = () =>
      [...(this._subEl || this._menuEl).querySelectorAll('[role="menuitem"]')]
    const move = (delta) => {
      const els = focusables()
      if (!els.length) return
      this._focusIdx = (this._focusIdx + delta + els.length) % els.length
      els.forEach((el, i) => el.classList.toggle('ctx-menu-focus', i === this._focusIdx))
      els[this._focusIdx].focus()
    }
    switch (e.key) {
      case 'Escape':
        e.stopPropagation()
        this._close(true)
        break
      case 'ArrowDown':
        e.preventDefault()
        move(1)
        break
      case 'ArrowUp':
        e.preventDefault()
        move(-1)
        break
      case 'ArrowRight': {
        e.preventDefault()
        const el = focusables()[this._focusIdx]
        if (el) el.dispatchEvent(new Event('mouseenter'))
        if (this._subEl) {
          this._focusIdx = -1
          this._keyboardIn = 'sub'
          move(1)
        }
        break
      }
      case 'ArrowLeft':
        e.preventDefault()
        if (this._subEl) {
          this._closeSub()
          this._focusIdx = -1
          move(1)
        }
        break
      case 'Enter': {
        e.preventDefault()
        focusables()[this._focusIdx]?.click()
        break
      }
    }
  },

  _closeSub() {
    if (this._subEl) {
      this._subEl.remove()
      this._subEl = null
    }
  },

  _close(refocus = false) {
    this._closeSub()
    if (this._menuEl) {
      this._menuEl.remove()
      this._menuEl = null
      if (refocus && this._trigger) this._trigger.focus?.()
    }
    this._trigger = null
    this._focusIdx = -1
  },
}
