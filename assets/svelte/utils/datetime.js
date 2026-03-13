/**
 * Shared datetime utilities for Svelte components
 */

/**
 * Parse datetime from various formats (Date object, ISO string, Go format string)
 * @param {Date|string|null} v - The value to parse
 * @returns {Date|null} - Parsed Date object or null
 */
export function parseDateLike(v) {
  if (!v) return null

  // Already a Date object
  if (v instanceof Date && !isNaN(v)) return v

  // Try ISO format first
  const d1 = new Date(v)
  if (!isNaN(d1)) return d1

  // Try Go format: "YYYY-MM-DD HH:MM:SS ..."
  const parts = String(v).split(" ")
  if (parts.length >= 2) {
    const isoish = parts[0] + "T" + parts[1]
    const d2 = new Date(isoish)
    if (!isNaN(d2)) return d2
  }

  return null
}

/**
 * Format relative time from a date (e.g., "5m ago", "2h ago")
 * @param {Date|string|null} date - The date to format
 * @returns {string} - Formatted relative time
 */
export function relativeFrom(date) {
  if (!date) return "—"

  const parsed = parseDateLike(date)
  if (!parsed) return "—"

  const secs = Math.max(0, Math.floor((Date.now() - parsed.getTime()) / 1000))
  const m = Math.floor(secs / 60)
  const h = Math.floor(m / 60)
  const mm = m % 60

  if (h > 0) return `${h}h ${mm}m ago`
  if (m > 0) return `${m}m ago`
  return `${secs}s ago`
}

/**
 * Format elapsed time from a date (e.g., "5m", "2h 30m")
 * @param {Date|string|null} date - The start date
 * @returns {string} - Formatted elapsed time
 */
export function elapsedTime(date) {
  if (!date) return "—"

  const parsed = parseDateLike(date)
  if (!parsed) return "—"

  const secs = Math.max(0, Math.floor((Date.now() - parsed.getTime()) / 1000))
  const m = Math.floor(secs / 60)
  const h = Math.floor(m / 60)
  const mm = m % 60

  if (h > 0) return `${h}h ${mm}m`
  if (m > 0) return `${m}m`
  return `${secs}s`
}

/**
 * Format date to short string (e.g., "Jan 15")
 * @param {Date|string|null} date - The date to format
 * @returns {string} - Formatted short date
 */
export function formatDateShort(date) {
  if (!date) return "—"

  const parsed = parseDateLike(date)
  if (!parsed) return "—"

  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return `${months[parsed.getMonth()]} ${parsed.getDate()}`
}

/**
 * Format date to full string for tooltips
 * @param {Date|string|null} date - The date to format
 * @returns {string} - Formatted full datetime
 */
export function formatDateFull(date) {
  if (!date) return ""

  const parsed = parseDateLike(date)
  if (!parsed) return ""

  return parsed.toISOString().replace('T', ' ').substring(0, 19) + ' UTC'
}

/**
 * Truncate ID to first N characters
 * @param {string|null} id - The ID to truncate
 * @param {number} length - Number of characters to keep (default: 8)
 * @returns {string} - Truncated ID
 */
export function shortId(id, length = 8) {
  return id ? id.slice(0, length) : ""
}

/**
 * Format time to HH:MM display
 * @param {Date|string|null} timestamp - The timestamp to format
 * @returns {string} - Formatted time (HH:MM)
 */
export function formatTime(timestamp) {
  if (!timestamp) return '—'

  const parsed = parseDateLike(timestamp)
  if (!parsed) return '—'

  return parsed.toLocaleTimeString(undefined, {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false
  })
}

/**
 * Format date with relative labels (Today/Yesterday) or short date
 * @param {Date|string|null} dateStr - The date to format
 * @returns {string} - Formatted date ("Today", "Yesterday", or "Jan 15, 2024")
 */
export function formatDateRelative(dateStr) {
  if (!dateStr) return ''

  const date = parseDateLike(dateStr)
  if (!date) return ''

  const today = new Date()
  const tomorrow = new Date(today)
  tomorrow.setDate(tomorrow.getDate() + 1)
  const yesterday = new Date(today)
  yesterday.setDate(yesterday.getDate() - 1)

  if (date.toDateString() === today.toDateString()) return 'Today'
  if (date.toDateString() === tomorrow.toDateString()) return 'Tomorrow'
  if (date.toDateString() === yesterday.toDateString()) return 'Yesterday'

  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric'
  })
}

/**
 * Format date and time for display (e.g., "Jan 15, 2024 2:30 PM")
 * @param {Date|string|null} dateStr - The date to format
 * @returns {string} - Formatted datetime
 */
export function formatDateTime(dateStr) {
  if (!dateStr) return ''

  const date = parseDateLike(dateStr)
  if (!date) return ''

  try {
    return date.toLocaleString(undefined, {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    })
  } catch (e) {
    return dateStr
  }
}
