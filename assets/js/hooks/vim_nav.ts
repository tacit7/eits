// assets/js/hooks/vim_nav.ts
import { COMMANDS, type Command } from "./vim_nav_commands"

const EDITABLE_TAGS = new Set(["INPUT", "TEXTAREA", "SELECT"])

export function isEditableTarget(el: Element | EventTarget | null): boolean {
  if (!el || !(el instanceof HTMLElement)) return false
  if (EDITABLE_TAGS.has(el.tagName)) return true
  if (el.isContentEditable || el.getAttribute("contenteditable") === "true") return true
  if (el.getAttribute("role") === "textbox") return true
  return false
}

export function keyFromEvent(event: KeyboardEvent): string {
  if (event.key === " ") return "Space"
  return event.key.length === 1 ? event.key.toLowerCase() : event.key
}

export function matchesKnownBindingOrPrefix(buffer: string[], key: string): boolean {
  const sequence = [...buffer, key]
  return COMMANDS.some(cmd => {
    for (let i = 0; i < sequence.length; i++) {
      if (cmd.keys[i] !== sequence[i]) return false
    }
    return true
  })
}

// Re-export Command type for use in Task 3 hook implementation
export type { Command }
