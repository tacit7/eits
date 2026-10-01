// EditorLayout hook
//
// Owns the file-editor layout state on the client:
//   <html data-editor-mode="hidden|single|split">
//   <html style="--editor-split-width: <px>">
//
// Modes:
//   hidden — no editor pane (default; main content full-width)
//   single — editor replaces main content (rail expands, main hidden)
//   split  — editor + main side by side, draggable handle
//
// The mode is derived from:
//   - whether the pane has tabs (data-has-tabs on the pane element)
//   - user preference (localStorage "editor_mode": "single" | "split")
//   - whether the current route allows split (data-allow-split on #app-shell)
//   - mobile viewport (forces single regardless of preference)
//
// Persists mode + split width to localStorage so they survive reloads.
// Source of truth lives on <html> (root layout, never morphdom-patched).

const STORAGE_MODE = "editor_mode"
const STORAGE_WIDTH = "editor_split_width"
const MIN_W = 320
const MIN_MAIN = 480

function clampWidth(w) {
  const max = Math.max(MIN_W, window.innerWidth - MIN_MAIN)
  return Math.max(MIN_W, Math.min(w, max))
}

function isMobile() {
  return window.matchMedia("(max-width: 767px)").matches
}

function allowSplit() {
  return document.getElementById("app-shell")?.dataset?.allowSplit === "true"
}

function preferredMode() {
  const v = localStorage.getItem(STORAGE_MODE)
  return v === "split" ? "split" : "single"
}

function paneHasTabs() {
  return document.getElementById("file-editor-pane")?.dataset?.hasTabs === "true"
}

// Compute the effective mode given current state.
// Rules:
//   - If split is allowed (route + viewport) AND user prefers split → "split"
//     (pane stays visible even with no tabs — empty state)
//   - Else if there are tabs → "single"
//   - Else → "hidden"
function effectiveMode() {
  if (allowSplit() && !isMobile() && preferredMode() === "split") return "split"
  if (paneHasTabs()) return "single"
  return "hidden"
}

function applyMode() {
  document.documentElement.setAttribute("data-editor-mode", effectiveMode())
}

function applyWidth(px) {
  const w = clampWidth(px)
  document.documentElement.style.setProperty("--editor-split-width", `${w}px`)
  return w
}

function restoreWidth() {
  const saved = parseInt(localStorage.getItem(STORAGE_WIDTH) || "", 10)
  const w = Number.isFinite(saved) ? saved : Math.round(window.innerWidth / 2)
  applyWidth(w)
}

// Step size (px) for keyboard-driven resize on the splitter.
const KEY_STEP = 20

export const EditorLayout = {
  mounted() {
    if (!localStorage.getItem(STORAGE_MODE)) {
      localStorage.setItem(STORAGE_MODE, "single")
    }

    restoreWidth()
    applyMode()

    // Re-evaluate mode whenever the pane's data-has-tabs flips.
    this._mo = new MutationObserver(applyMode)
    this._mo.observe(this.el, { attributes: true, attributeFilter: ["data-has-tabs"] })

    // Re-evaluate on viewport resize (mobile threshold + width clamp)
    this._onResize = () => {
      const cur = parseInt(localStorage.getItem(STORAGE_WIDTH) || "", 10)
      if (Number.isFinite(cur)) applyWidth(cur)
      applyMode()
    }
    window.addEventListener("resize", this._onResize)

    // Toolbar toggle (single ↔ split). Dispatched from the toolbar button.
    this._onToggle = () => {
      const next = preferredMode() === "split" ? "single" : "split"
      localStorage.setItem(STORAGE_MODE, next)
      applyMode()
    }
    window.addEventListener("editor:toggle-split", this._onToggle)

    // Splitter drag handle
    const splitter = document.getElementById("editor-splitter")
    if (splitter) {
      // Keep drag listeners as instance vars so destroyed() can always clean up,
      // even if the hook is torn down while a drag is in progress.
      this._dragMove = null
      this._dragUp = null
      this._dragCancel = null

      const endDrag = () => {
        document.removeEventListener("pointermove", this._dragMove)
        document.removeEventListener("pointerup", this._dragUp)
        document.removeEventListener("pointercancel", this._dragCancel)
        this._dragMove = null
        this._dragUp = null
        this._dragCancel = null
        document.body.style.cursor = ""
        document.body.style.userSelect = ""
        if (this._lastDragW) {
          localStorage.setItem(STORAGE_WIDTH, String(this._lastDragW))
        }
      }

      this._onPointerDown = (e) => {
        e.preventDefault()
        document.body.style.cursor = "col-resize"
        document.body.style.userSelect = "none"

        this._dragMove = (ev) => {
          const pane = document.getElementById("file-editor-pane")
          if (!pane) return
          const left = pane.getBoundingClientRect().left
          const w = applyWidth(ev.clientX - left)
          this._lastDragW = w
          // Keep ARIA value in sync while dragging
          splitter.setAttribute("aria-valuenow", String(w))
        }
        this._dragUp = endDrag
        this._dragCancel = endDrag

        document.addEventListener("pointermove", this._dragMove)
        document.addEventListener("pointerup", this._dragUp)
        document.addEventListener("pointercancel", this._dragCancel)
      }

      // Keyboard resize: ArrowLeft / ArrowRight move the splitter by KEY_STEP px.
      this._onKeyDown = (e) => {
        if (e.key !== "ArrowLeft" && e.key !== "ArrowRight") return
        e.preventDefault()
        const cur = parseInt(
          document.documentElement.style.getPropertyValue("--editor-split-width") || "0",
          10,
        )
        const next = applyWidth(cur + (e.key === "ArrowRight" ? KEY_STEP : -KEY_STEP))
        localStorage.setItem(STORAGE_WIDTH, String(next))
        splitter.setAttribute("aria-valuenow", String(next))
      }

      splitter.addEventListener("pointerdown", this._onPointerDown)
      splitter.addEventListener("keydown", this._onKeyDown)
      this._splitter = splitter

      // Sync initial ARIA value
      this._syncAriaValues = () => {
        const cur = parseInt(
          document.documentElement.style.getPropertyValue("--editor-split-width") || "0",
          10,
        )
        const min = MIN_W
        const max = Math.max(MIN_W, window.innerWidth - MIN_MAIN)
        splitter.setAttribute("aria-valuemin", String(min))
        splitter.setAttribute("aria-valuemax", String(max))
        splitter.setAttribute("aria-valuenow", String(cur))
      }
      this._syncAriaValues()
    }
  },

  updated() {
    // Re-evaluate after LiveView patches (route change might flip allow-split).
    applyMode()
    // Re-sync ARIA bounds after layout changes.
    if (this._syncAriaValues) this._syncAriaValues()
  },

  destroyed() {
    document.documentElement.setAttribute("data-editor-mode", "hidden")
    window.removeEventListener("resize", this._onResize)
    window.removeEventListener("editor:toggle-split", this._onToggle)
    if (this._mo) this._mo.disconnect()
    if (this._splitter) {
      if (this._onPointerDown) this._splitter.removeEventListener("pointerdown", this._onPointerDown)
      if (this._onKeyDown) this._splitter.removeEventListener("keydown", this._onKeyDown)
    }
    // Clean up any in-progress drag (navigation mid-drag scenario)
    if (this._dragMove) document.removeEventListener("pointermove", this._dragMove)
    if (this._dragUp) document.removeEventListener("pointerup", this._dragUp)
    if (this._dragCancel) document.removeEventListener("pointercancel", this._dragCancel)
    document.body.style.cursor = ""
    document.body.style.userSelect = ""
  },
}

// Window-level listeners. file-editor-open/close are server-pushed in
// FileActions; allow-split changes come from layout re-renders. We re-derive
// mode from current DOM state on every event.
export function installEditorWindowListeners() {
  const reapply = () => {
    if (document.getElementById("file-editor-pane")) {
      document.documentElement.setAttribute("data-editor-mode", effectiveMode())
    } else {
      document.documentElement.setAttribute("data-editor-mode", "hidden")
    }
  }
  window.addEventListener("phx:file-editor-open", reapply)
  window.addEventListener("phx:file-editor-close", reapply)
  window.addEventListener("phx:page-loading-stop", reapply)
}
