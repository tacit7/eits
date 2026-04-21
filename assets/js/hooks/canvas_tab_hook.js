let _listenerCount = 0

const SHORTCUTS = [
  { keys: "⌘ 1 – 9",     desc: "Switch to canvas tab" },
  { keys: "Esc",          desc: "Minimize focused window" },
  { keys: "Space + drag", desc: "Pan canvas viewport" },
  { keys: "Drag title",   desc: "Move window" },
  { keys: "Drag corner",  desc: "Resize window" },
  { keys: "Click window", desc: "Bring to front" },
  { keys: "?",            desc: "Show this help" },
]

function closeHelp() {
  const el = document.getElementById("canvas-shortcuts-help")
  if (el) el.style.display = "none"
}

function getOrCreateHelp() {
  let el = document.getElementById("canvas-shortcuts-help")
  if (el) return el

  el = document.createElement("div")
  el.id = "canvas-shortcuts-help"
  el.style.cssText = "position:fixed;inset:0;z-index:200;display:none;align-items:center;justify-content:center"

  const backdrop = document.createElement("div")
  backdrop.style.cssText = "position:absolute;inset:0;background:oklch(var(--b3)/0.6)"
  backdrop.addEventListener("click", closeHelp)

  const card = document.createElement("div")
  card.style.cssText = "position:relative;z-index:1;min-width:280px"
  card.className = "card bg-base-100 shadow-xl"

  const body = document.createElement("div")
  body.className = "card-body p-5 gap-3"

  const title = document.createElement("h3")
  title.className = "font-semibold text-sm text-base-content/80"
  title.textContent = "Canvas Shortcuts"

  const table = document.createElement("table")
  table.className = "w-full text-xs"
  SHORTCUTS.forEach(({ keys, desc }) => {
    const tr = document.createElement("tr")
    tr.innerHTML = `<td class="py-1 pr-4 font-mono text-base-content/50 whitespace-nowrap">${keys}</td><td class="py-1 text-base-content/70">${desc}</td>`
    table.appendChild(tr)
  })

  const hint = document.createElement("p")
  hint.className = "text-[10px] text-base-content/30 mt-1"
  hint.textContent = "Press Esc or click outside to close"

  body.append(title, table, hint)
  card.appendChild(body)
  el.append(backdrop, card)
  document.body.appendChild(el)
  return el
}

function isHelpVisible() {
  const el = document.getElementById("canvas-shortcuts-help")
  return el && el.style.display !== "none"
}

function onKeydown(e) {
  // Skip when typing in inputs
  if (e.target.matches("input, textarea, [contenteditable]")) return

  if (e.key === "?") {
    if (isHelpVisible()) {
      closeHelp()
    } else {
      const help = getOrCreateHelp()
      help.style.display = "flex"
    }
    return
  }

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
    if (isHelpVisible()) {
      closeHelp()
      return
    }

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

// Attached to the tablist container — always in the DOM, so disconnect/reconnect
// fires reliably regardless of how many canvas tabs are open (including zero).
export const CanvasStatusHook = {
  disconnected() {
    document.getElementById(WS_BADGE_ID)?.classList.remove("hidden")
  },

  reconnected() {
    document.getElementById(WS_BADGE_ID)?.classList.add("hidden")
  }
}

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
  }
}
