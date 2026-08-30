export type Mode = "normal" | "insert"

export function createStatusbar(): HTMLElement {
  const el = document.createElement("div")
  el.id = "vim-nav-statusbar"
  el.setAttribute("aria-hidden", "true")
  el.style.cssText = [
    "position:fixed",
    "bottom:12px",
    "right:16px",
    "z-index:9999",
    "font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
    "font-size:var(--text-mini)",
    "padding:2px 6px",
    "border-radius:var(--radius-selector)",
    "pointer-events:none",
    "background:transparent",
  ].join(";")
  return el
}

export function updateStatusbar(el: HTMLElement, mode: Mode, count = 0): void {
  if (mode === "normal") {
    el.textContent = count > 0 ? `[ NORMAL ] ${count}` : "[ NORMAL ]"
    el.style.color = "var(--color-base-content)"
    el.style.opacity = "0.55"
  } else {
    el.textContent = "[ INSERT ]"
    el.style.color = "var(--color-info)"
    el.style.opacity = "0.9"
  }
}
