export function _generateHintLabels(count: number): string[] {
  const alpha = "abcdefghijklmnopqrstuvwxyz"
  const labels: string[] = []
  for (let i = 0; labels.length < count && i < alpha.length; i++) {
    labels.push(alpha[i])
  }
  for (let i = 0; labels.length < count && i < alpha.length; i++) {
    for (let j = 0; labels.length < count && j < alpha.length; j++) {
      labels.push(alpha[i] + alpha[j])
    }
  }
  return labels
}

export function createHintOverlay(items: HTMLElement[], labels: string[]): HTMLElement {
  const overlay = document.createElement("div")
  overlay.id = "vim-nav-hints"
  overlay.style.cssText = "position:fixed;inset:0;pointer-events:none;z-index:9999"

  items.forEach((item, i) => {
    const rect = item.getBoundingClientRect()
    const badge = document.createElement("span")
    badge.dataset.hintLabel = labels[i]
    badge.textContent = labels[i]
    badge.style.cssText = [
      "position:fixed",
      `top:${rect.top + 4}px`,
      `left:${rect.left + 4}px`,
      "background:var(--color-warning,#f59e0b)",
      "color:var(--color-warning-content,#000)",
      "font-family:monospace",
      "font-size:11px",
      "font-weight:700",
      "line-height:1",
      "padding:1px 4px",
      "border-radius:3px",
      "pointer-events:none",
      "z-index:9999",
      "letter-spacing:0.05em",
    ].join(";")
    overlay.appendChild(badge)
  })

  return overlay
}

export function filterHintBadges(
  overlayEl: HTMLElement,
  prefix: string,
  hintLabels: Array<{ label: string; index: number }>,
): Array<{ label: string; index: number }> {
  const matches = hintLabels.filter(h => h.label.startsWith(prefix))

  overlayEl.querySelectorAll<HTMLElement>("[data-hint-label]").forEach(badge => {
    const label = badge.dataset.hintLabel!
    if (label.startsWith(prefix)) {
      badge.style.opacity = "1"
      const typed = label.slice(0, prefix.length)
      const rest = label.slice(prefix.length)
      badge.innerHTML = typed ? `<span style="opacity:0.5">${typed}</span>${rest}` : label
    } else {
      badge.style.opacity = "0.15"
    }
  })

  return matches
}
