import { describe, it, expect } from 'vitest'

// Re-export getSnapZone for testing by duplicating the pure function — the hook
// file uses export const for the hook itself, not for helpers. Keep in sync.
const SNAP_THRESHOLD = 80

function getSnapZone(cursorX, cursorY, canvasW, canvasH) {
  canvasW = Math.round(canvasW)
  canvasH = Math.round(canvasH)

  const nearLeft   = cursorX < SNAP_THRESHOLD
  const nearRight  = cursorX > canvasW - SNAP_THRESHOLD
  const nearTop    = cursorY < SNAP_THRESHOLD
  const nearBottom = cursorY > canvasH - SNAP_THRESHOLD

  const hw = Math.round(canvasW / 2)
  const hh = Math.round(canvasH / 2)

  if (nearLeft && nearTop)     return { left: 0,  top: 0,  width: hw,     height: hh }
  if (nearRight && nearTop)    return { left: hw, top: 0,  width: hw,     height: hh }
  if (nearLeft && nearBottom)  return { left: 0,  top: hh, width: hw,     height: hh }
  if (nearRight && nearBottom) return { left: hw, top: hh, width: hw,     height: hh }
  if (nearLeft)                return { left: 0,  top: 0,  width: hw,     height: canvasH }
  if (nearRight)               return { left: hw, top: 0,  width: hw,     height: canvasH }
  if (nearTop)                 return { left: 0,  top: 0,  width: canvasW, height: hh }
  if (nearBottom)              return { left: 0,  top: hh, width: canvasW, height: hh }
  return null
}

describe('getSnapZone', () => {
  const W = 1000
  const H = 800

  it('returns null when cursor is in center', () => {
    expect(getSnapZone(500, 400, W, H)).toBeNull()
  })

  it('snaps top-left corner', () => {
    expect(getSnapZone(40, 40, W, H)).toEqual({ left: 0, top: 0, width: 500, height: 400 })
  })

  it('snaps top-right corner', () => {
    expect(getSnapZone(960, 40, W, H)).toEqual({ left: 500, top: 0, width: 500, height: 400 })
  })

  it('snaps bottom-left corner', () => {
    expect(getSnapZone(40, 760, W, H)).toEqual({ left: 0, top: 400, width: 500, height: 400 })
  })

  it('snaps bottom-right corner', () => {
    expect(getSnapZone(960, 760, W, H)).toEqual({ left: 500, top: 400, width: 500, height: 400 })
  })

  it('snaps left half', () => {
    expect(getSnapZone(40, 400, W, H)).toEqual({ left: 0, top: 0, width: 500, height: 800 })
  })

  it('snaps right half', () => {
    expect(getSnapZone(960, 400, W, H)).toEqual({ left: 500, top: 0, width: 500, height: 800 })
  })

  it('snaps top half', () => {
    expect(getSnapZone(500, 40, W, H)).toEqual({ left: 0, top: 0, width: 1000, height: 400 })
  })

  it('snaps bottom half', () => {
    expect(getSnapZone(500, 760, W, H)).toEqual({ left: 0, top: 400, width: 1000, height: 400 })
  })

  it('rounds fractional canvas dimensions to integers', () => {
    const snap = getSnapZone(40, 40, 1000.7, 800.3)
    expect(Number.isInteger(snap.width)).toBe(true)
    expect(Number.isInteger(snap.height)).toBe(true)
    expect(snap).toEqual({ left: 0, top: 0, width: 501, height: 400 })
  })
})
