let _listenerCount = 0

function onKeydown(e) {
  if (e.metaKey && e.key >= "1" && e.key <= "9") {
    const n = parseInt(e.key, 10) - 1
    const tabs = document.querySelectorAll("[id^='canvas-tab-']")
    const tab = tabs[n]
    if (tab) {
      e.preventDefault()
      tab.click()
    }
    return
  }

  if (e.key === "Escape") {
    let maxZ = 0
    let focused = null
    document.querySelectorAll("[data-chat-window]").forEach(w => {
      const z = parseInt(w.style.zIndex, 10) || 0
      if (z > maxZ) { maxZ = z; focused = w }
    })
    if (focused) {
      const btn = focused.querySelector("[data-minimize-btn]")
      if (btn) btn.click()
    }
  }
}

const WS_BADGE_ID = "canvas-ws-badge"

export const CanvasTabHook = {
  mounted() {
    this.el.addEventListener("dblclick", () => {
      this.pushEvent("start_rename", {"canvas-id": this.el.dataset.canvasId})
    })

    if (_listenerCount === 0) {
      document.addEventListener("keydown", onKeydown)
    }
    _listenerCount++
  },

  destroyed() {
    _listenerCount--
    if (_listenerCount === 0) {
      document.removeEventListener("keydown", onKeydown)
    }
  },

  disconnected() {
    document.getElementById(WS_BADGE_ID)?.classList.remove("hidden")
  },

  reconnected() {
    document.getElementById(WS_BADGE_ID)?.classList.add("hidden")
  }
}
