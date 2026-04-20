// assets/svelte/utils/messageGrouping.test.js
import { describe, it, expect } from 'vitest'
import {
  messageTime,
  isSystemMessage,
  senderKey,
  sameCalendarDay,
  isNewDate,
  isGrouped,
  GROUP_WINDOW_MS,
} from './messageGrouping.js'

// Helpers
const msg = (overrides) => ({
  sender_role: 'agent',
  session_id: 42,
  inserted_at: '2026-04-20T10:00:00Z',
  ...overrides,
})

describe('messageTime', () => {
  it('returns null for missing inserted_at', () => {
    expect(messageTime({})).toBe(null)
    expect(messageTime(null)).toBe(null)
  })

  it('returns null for invalid date string', () => {
    expect(messageTime({ inserted_at: 'not-a-date' })).toBe(null)
  })

  it('returns epoch ms for valid ISO string', () => {
    const t = messageTime({ inserted_at: '2026-04-20T10:00:00Z' })
    expect(typeof t).toBe('number')
    expect(t).toBeGreaterThan(0)
  })
})

describe('isSystemMessage', () => {
  it('returns true for sender_role system', () => {
    expect(isSystemMessage({ sender_role: 'system' })).toBe(true)
  })

  it('returns true for type system', () => {
    expect(isSystemMessage({ sender_role: 'agent', type: 'system' })).toBe(true)
  })

  it('returns false for agent message', () => {
    expect(isSystemMessage(msg())).toBe(false)
  })

  it('returns false for null', () => {
    expect(isSystemMessage(null)).toBe(false)
  })
})

describe('senderKey', () => {
  it('returns "user" for user messages', () => {
    expect(senderKey({ sender_role: 'user' })).toBe('user')
  })

  it('returns session key for agent with session_id', () => {
    expect(senderKey(msg({ session_id: 99 }))).toBe('session:99')
  })

  it('returns null for agent without session_id', () => {
    expect(senderKey({ sender_role: 'agent' })).toBe(null)
  })

  it('returns null for system messages', () => {
    expect(senderKey({ sender_role: 'system' })).toBe(null)
  })

  it('returns null for null input', () => {
    expect(senderKey(null)).toBe(null)
  })
})

describe('sameCalendarDay', () => {
  it('returns true for same UTC day', () => {
    const a = { inserted_at: '2026-04-20T10:00:00Z' }
    const b = { inserted_at: '2026-04-20T23:59:00Z' }
    expect(sameCalendarDay(a, b)).toBe(true)
  })

  it('returns false for different days', () => {
    const a = { inserted_at: '2026-04-20T10:00:00Z' }
    const b = { inserted_at: '2026-04-21T10:00:00Z' }
    expect(sameCalendarDay(a, b)).toBe(false)
  })

  it('returns false when either timestamp is invalid', () => {
    const a = { inserted_at: 'bad' }
    const b = { inserted_at: '2026-04-20T10:00:00Z' }
    expect(sameCalendarDay(a, b)).toBe(false)
  })
})

describe('isNewDate', () => {
  it('returns true when there is no previous message', () => {
    expect(isNewDate(msg(), null)).toBe(true)
    expect(isNewDate(msg(), undefined)).toBe(true)
  })

  it('returns false when same day', () => {
    const a = msg({ inserted_at: '2026-04-20T10:00:00Z' })
    const b = msg({ inserted_at: '2026-04-20T11:00:00Z' })
    expect(isNewDate(b, a)).toBe(false)
  })

  it('returns true when different day', () => {
    const a = msg({ inserted_at: '2026-04-20T10:00:00Z' })
    const b = msg({ inserted_at: '2026-04-21T10:00:00Z' })
    expect(isNewDate(b, a)).toBe(true)
  })

  it('returns false for null message', () => {
    expect(isNewDate(null, msg())).toBe(false)
  })
})

describe('isGrouped', () => {
  it('groups same sender within 5 minutes', () => {
    const a = msg({ inserted_at: '2026-04-20T10:00:00Z' })
    const b = msg({ inserted_at: '2026-04-20T10:04:00Z' })
    expect(isGrouped(b, a)).toBe(true)
  })

  it('does not group messages > 5 minutes apart', () => {
    const a = msg({ inserted_at: '2026-04-20T10:00:00Z' })
    const b = msg({ inserted_at: '2026-04-20T10:06:00Z' })
    expect(isGrouped(b, a)).toBe(false)
  })

  it('does not group different session ids', () => {
    const a = msg({ session_id: 1 })
    const b = msg({ session_id: 2 })
    expect(isGrouped(b, a)).toBe(false)
  })

  it('does not group across midnight', () => {
    const a = msg({ inserted_at: '2026-04-20T23:58:00Z' })
    const b = msg({ inserted_at: '2026-04-21T00:01:00Z' })
    expect(isGrouped(b, a)).toBe(false)
  })

  it('does not group system messages', () => {
    const a = msg()
    const b = msg({ sender_role: 'system' })
    expect(isGrouped(b, a)).toBe(false)
  })

  it('does not group when prev is system', () => {
    const a = msg({ sender_role: 'system' })
    const b = msg()
    expect(isGrouped(b, a)).toBe(false)
  })

  it('does not group negative deltas', () => {
    const a = msg({ inserted_at: '2026-04-20T10:05:00Z' })
    const b = msg({ inserted_at: '2026-04-20T10:00:00Z' })
    expect(isGrouped(b, a)).toBe(false)
  })

  it('does not group agent without session_id', () => {
    const a = { sender_role: 'agent', inserted_at: '2026-04-20T10:00:00Z' }
    const b = { sender_role: 'agent', inserted_at: '2026-04-20T10:01:00Z' }
    expect(isGrouped(b, a)).toBe(false)
  })

  it('returns false when either message is null', () => {
    expect(isGrouped(null, msg())).toBe(false)
    expect(isGrouped(msg(), null)).toBe(false)
  })
})
