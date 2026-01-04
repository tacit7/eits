/**
 * Clipboard utilities for copying text and formatting UUIDs
 */

/**
 * Format a UUID string with proper dashes
 * @param {string} id - The UUID to format (with or without dashes)
 * @returns {string} - Formatted UUID or original string if invalid
 */
export function formatUUID(id) {
  if (!id) return ''

  // Remove any existing dashes
  const clean = id.replace(/-/g, '')

  // Return as-is if not valid UUID length
  if (clean.length !== 32) return id

  // Format as UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  return `${clean.slice(0, 8)}-${clean.slice(8, 12)}-${clean.slice(12, 16)}-${clean.slice(16, 20)}-${clean.slice(20)}`
}

/**
 * Copy text to clipboard with optional UUID formatting
 * @param {string} text - The text to copy
 * @param {Object} options - Options object
 * @param {boolean} options.formatAsUUID - Whether to format as UUID before copying
 * @returns {Promise} - Promise that resolves when copy is complete
 */
export function copyToClipboard(text, { formatAsUUID = false } = {}) {
  const textToCopy = formatAsUUID ? formatUUID(text) : text

  return navigator.clipboard.writeText(textToCopy)
    .then(() => {
      console.log('Copied to clipboard:', textToCopy)
      return textToCopy
    })
    .catch(err => {
      console.error('Failed to copy to clipboard:', err)
      throw err
    })
}
