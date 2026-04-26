// assets/js/hooks/vim_nav_commands.ts

export type NavigateAction = {
  kind: "navigate"
  path: string
  relative?: boolean  // if true, prepend data-vim-project-path from shell el
}

export type PushEventAction = {
  kind: "push_event"
  event: string
  payload?: Record<string, unknown>
  target: "shell" | "active_view"
}

export type ClientAction = {
  kind: "client"
  name: "help" | "history_back" | "history_forward" | "command_palette"
}

export type CommandAction = NavigateAction | PushEventAction | ClientAction

export type CommandGroup = "navigation" | "toggle" | "create" | "global" | "context"

export interface Command {
  id: string
  label: string
  keys: string[]
  group: CommandGroup
  action: CommandAction
  scope?: string
}

export const COMMANDS: Command[] = [
  // g — page navigation
  { id: "nav.sessions", label: "Go to Sessions", keys: ["g", "s"], group: "navigation",
    action: { kind: "navigate", path: "/sessions" } },
  { id: "nav.tasks",    label: "Go to Tasks",    keys: ["g", "t"], group: "navigation",
    action: { kind: "navigate", path: "tasks", relative: true } },
  { id: "nav.notes",    label: "Go to Notes",    keys: ["g", "n"], group: "navigation",
    action: { kind: "navigate", path: "notes", relative: true } },
  { id: "nav.canvas",   label: "Go to Canvas",   keys: ["g", "w"], group: "navigation",
    action: { kind: "navigate", path: "/canvases" } },
  { id: "nav.agents",   label: "Go to Agents",   keys: ["g", "a"], group: "navigation",
    action: { kind: "navigate", path: "agents", relative: true } },
  { id: "nav.settings", label: "Go to Settings", keys: ["g", ","], group: "navigation",
    action: { kind: "navigate", path: "/settings" } },
  // global
  { id: "global.help",  label: "Keybinding Help", keys: ["?"], group: "global",
    action: { kind: "client", name: "help" } },
]

// All valid first keys in multi-key sequences
export const PREFIXES: Set<string> = new Set(
  COMMANDS.filter(c => c.keys.length > 1).map(c => c.keys[0])
)
