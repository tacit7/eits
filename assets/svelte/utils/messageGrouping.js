// assets/svelte/utils/messageGrouping.js

export const GROUP_WINDOW_MS = 5 * 60 * 1000

export function messageTime(message) {
  if (!message?.inserted_at) return null
  const time = new Date(message.inserted_at).getTime()
  return Number.isNaN(time) ? null : time
}

export function isSystemMessage(message) {
  return message?.sender_role === 'system' || message?.type === 'system'
}

export function senderKey(message) {
  if (!message || isSystemMessage(message)) return null
  if (message.sender_role === 'user') return 'user'
  if (message.session_id) return `session:${message.session_id}`
  return null
}

export function sameCalendarDay(a, b) {
  const at = messageTime(a)
  const bt = messageTime(b)
  if (at === null || bt === null) return false
  const da = new Date(at), db = new Date(bt)
  return da.getUTCFullYear() === db.getUTCFullYear()
    && da.getUTCMonth() === db.getUTCMonth()
    && da.getUTCDate() === db.getUTCDate()
}

export function isNewDate(message, prev) {
  if (!message) return false
  if (!prev) return true
  return !sameCalendarDay(message, prev)
}

export function isGrouped(message, prev) {
  if (!message || !prev) return false
  if (isSystemMessage(message) || isSystemMessage(prev)) return false
  const key = senderKey(message)
  const prevKey = senderKey(prev)
  if (!key || key !== prevKey) return false
  if (!sameCalendarDay(message, prev)) return false
  const time = messageTime(message)
  const prevTime = messageTime(prev)
  if (time === null || prevTime === null) return false
  const delta = time - prevTime
  return delta >= 0 && delta <= GROUP_WINDOW_MS
}
