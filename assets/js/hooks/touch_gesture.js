/**
 * Touch gesture detection utility.
 *
 * Feature-gates itself to touch-capable devices. Ignores gestures that
 * originate inside form controls and cancels when vertical scroll is dominant.
 */

export const TOUCH_DEVICE =
  typeof window !== "undefined" &&
  ("ontouchstart" in window || navigator.maxTouchPoints > 0)

function isFormControl(el) {
  if (!el) return false
  const tag = el.tagName
  if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return true
  if (el.isContentEditable) return true
  return !!el.closest("input, textarea, select, [contenteditable]")
}

/**
 * Creates a swipe detector that fires onSwipeLeft / onSwipeRight callbacks.
 *
 * @param {object} opts
 * @param {Function} [opts.onSwipeLeft]
 * @param {Function} [opts.onSwipeRight]
 * @param {number}   [opts.minDistance=48]  - px of horizontal travel required
 * @param {number}   [opts.minVelocity=180] - px/s required
 */
export function createSwipeDetector({
  onSwipeLeft,
  onSwipeRight,
  minDistance = 48,
  minVelocity = 180,
} = {}) {
  let startX = 0, startY = 0, startTime = 0
  let tracking = false

  function onTouchStart(e) {
    if (isFormControl(e.target)) return
    if (e.touches.length !== 1) { tracking = false; return }
    const t = e.touches[0]
    startX = t.clientX
    startY = t.clientY
    startTime = Date.now()
    tracking = true
  }

  function onTouchMove(e) {
    if (!tracking) return
    const t = e.touches[0]
    const dx = Math.abs(t.clientX - startX)
    const dy = Math.abs(t.clientY - startY)
    // Cancel when vertical scroll is dominant (dy > dx after 10px of travel)
    if (dy > 10 && dy > dx * 0.75) {
      tracking = false
    }
  }

  function onTouchEnd(e) {
    if (!tracking) { tracking = false; return }
    tracking = false
    const t = e.changedTouches[0]
    const dx = t.clientX - startX
    const dy = t.clientY - startY
    const dt = Math.max(Date.now() - startTime, 1)

    if (Math.abs(dy) > Math.abs(dx)) return       // vertical dominant
    if (Math.abs(dx) < minDistance) return         // too short
    if ((Math.abs(dx) / dt) * 1000 < minVelocity) return  // too slow

    if (dx < 0 && onSwipeLeft) onSwipeLeft(e)
    if (dx > 0 && onSwipeRight) onSwipeRight(e)
  }

  return { onTouchStart, onTouchMove, onTouchEnd }
}
