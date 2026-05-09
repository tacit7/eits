// Command palette utilities and logic
// Provides fuzzy search, scoring, rendering, and UI helpers

/**
 * Finds character positions matching a fuzzy search query in a label.
 * @param {string} label - The text to search
 * @param {string} q - The query string
 * @returns {Array|null} Array of matched positions, or null if no match
 */
export function fuzzyPositions(label, q) {
  const lc = label.toLowerCase()
  const positions = []
  let qi = 0
  for (let i = 0; i < lc.length && qi < q.length; i++) {
    if (lc[i] === q[qi]) { positions.push(i); qi++ }
  }
  return qi === q.length ? positions : null
}

/**
 * Scores a command based on how well it matches the query.
 * Higher scores indicate better matches (prefix > contains > fuzzy).
 * @param {Object} cmd - The command object
 * @param {string} q - The query string
 * @param {Array|null} positions - Character positions from fuzzyPositions()
 * @returns {number} Relevance score
 */
export function scoreCmd(cmd, q, positions) {
  const label = cmd.label.toLowerCase()
  let score = 0

  if (label === q) score += 200
  if (label.startsWith(q)) score += 100
  if (label.includes(q)) score += 50

  if (positions !== null) {
    score += 60
    let consecutive = 0
    for (let i = 1; i < positions.length; i++) {
      if (positions[i] === positions[i - 1] + 1) consecutive++
    }
    score += consecutive * 2
  }

  const kws = (cmd.keywords || []).join(" ").toLowerCase()
  if (kws && kws.includes(q)) score += 30
  if (cmd.hint && cmd.hint.toLowerCase().includes(q)) score += 15
  if (cmd.group && cmd.group.toLowerCase().includes(q)) score += 10

  return score
}

/**
 * Escapes HTML special characters to prevent XSS.
 * @param {any} value - The value to escape
 * @returns {string} HTML-safe string
 */
export function escapeHtml(value) {
  return String(value || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;")
}

/**
 * Wraps matched characters in a label with <mark> tags for highlighting.
 * @param {string} label - The label text
 * @param {Set} matchedPositions - Set of character positions to highlight
 * @returns {string} HTML string with marked matches
 */
export function highlightLabel(label, matchedPositions) {
  return [...label].map((char, i) =>
    matchedPositions.has(i)
      ? `<mark class="bg-transparent text-primary font-semibold">${escapeHtml(char)}</mark>`
      : escapeHtml(char)
  ).join("")
}

/**
 * Palette state and lifecycle management helpers.
 */

/**
 * Loads recent commands from localStorage.
 * @returns {Array} Array of recent command entries with {id, label, href, at}
 */
export function loadRecentCommands() {
  try {
    const parsed = JSON.parse(localStorage.getItem("command_palette_recent") || "[]")
    return Array.isArray(parsed) ? parsed : []
  } catch (_) { return [] }
}

/**
 * Saves a command to the recent commands list.
 * Maintains a sliding window of the 8 most recent commands.
 * @param {Object} cmd - The command object with {id, label, href, type}
 */
export function saveRecentCommand(cmd) {
  if (cmd.type !== "navigate") return
  const existing = loadRecentCommands().filter(e => e.href !== cmd.href)
  const next = [{ id: cmd.id, label: cmd.label, href: cmd.href, at: Date.now() }, ...existing].slice(0, 8)
  localStorage.setItem("command_palette_recent", JSON.stringify(next))
}

/**
 * Detects the user's platform from navigator.userAgentData or navigator.platform.
 * @returns {boolean} true if the user is on macOS
 */
export function detectMacOS() {
  return navigator.userAgentData
    ? navigator.userAgentData.platform === "macOS"
    : navigator.platform.toUpperCase().includes("MAC")
}

/**
 * Checks if a keyboard event matches the palette shortcut modifier.
 * Supports "auto" (Cmd on Mac, Ctrl elsewhere), "cmd", "ctrl", "alt".
 * @param {KeyboardEvent} e - The keyboard event
 * @param {string} shortcut - The shortcut mode (e.g. "auto", "cmd", "ctrl", "alt")
 * @param {boolean} isMac - Whether the user is on macOS
 * @returns {boolean} true if the modifier matches
 */
export function matchesModifier(e, shortcut, isMac) {
  if (shortcut === "cmd")  return e.metaKey
  if (shortcut === "ctrl") return e.ctrlKey
  if (shortcut === "alt")  return e.altKey
  // auto: on Mac accept both Cmd+K and Ctrl+K so either key works
  return isMac ? (e.metaKey || e.ctrlKey) : e.ctrlKey
}
