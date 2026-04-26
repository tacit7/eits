// assets/js/hooks/vim_nav_commands.ts

export type NavigateAction = {
  kind: "navigate"
  path: string
  relative?: boolean  // if true, resolve against current project path
}

export type PushEventAction = {
  kind: "push_event"
  event: string
  payload?: Record<string, unknown>
  target: "shell" | "active_view"
}

export type ClientAction = {
  kind: "client"
  name: "help" | "history_back" | "history_forward" | "command_palette" | "quick_create_note" | "quick_create_task"
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
    action: { kind: "navigate", path: "sessions", relative: true } },
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
  // t — toggle rail sections
  { id: "toggle.sessions",    label: "Toggle Sessions",        keys: ["t", "s"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "sessions" }, target: "shell" } },
  { id: "toggle.tasks",       label: "Toggle Tasks",           keys: ["t", "t"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "tasks" }, target: "shell" } },
  { id: "toggle.notes",       label: "Toggle Notes",           keys: ["t", "n"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "notes" }, target: "shell" } },
  { id: "toggle.files",       label: "Toggle Files",           keys: ["t", "f"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "files" }, target: "shell" } },
  { id: "toggle.canvas",      label: "Toggle Canvas",          keys: ["t", "w"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "canvas" }, target: "shell" } },
  { id: "toggle.chat",        label: "Toggle Chat",            keys: ["t", "c"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "chat" }, target: "shell" } },
  { id: "toggle.skills",      label: "Toggle Skills",          keys: ["t", "k"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "skills" }, target: "shell" } },
  { id: "toggle.teams",       label: "Toggle Teams",           keys: ["t", "m"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "teams" }, target: "shell" } },
  { id: "toggle.jobs",        label: "Toggle Jobs",            keys: ["t", "j"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "jobs" }, target: "shell" } },
  { id: "toggle.proj_picker", label: "Toggle Project Picker",  keys: ["t", "p"], group: "toggle",
    action: { kind: "push_event", event: "toggle_proj_picker", payload: {}, target: "shell" } },

  // n — create actions
  { id: "create.session", label: "New Session", keys: ["n", "s"], group: "create",
    action: { kind: "push_event", event: "toggle_new_session_drawer", payload: {}, target: "shell" } },
  { id: "create.task",    label: "New Task",    keys: ["n", "t"], group: "create",
    action: { kind: "client", name: "quick_create_task" } },
  { id: "create.note",    label: "New Note",    keys: ["n", "n"], group: "create",
    action: { kind: "client", name: "quick_create_note" } },
  { id: "create.agent",   label: "New Agent",   keys: ["n", "a"], group: "create",
    action: { kind: "push_event", event: "toggle_new_session_drawer", payload: {}, target: "shell" } },

  // global
  { id: "global.help",    label: "Keybinding Help",  keys: ["?"], group: "global",
    action: { kind: "client", name: "help" } },
  { id: "global.palette", label: "Command Palette",  keys: [":"], group: "global",
    action: { kind: "client", name: "command_palette" } },
  { id: "global.back",    label: "Go Back",          keys: ["["], group: "global",
    action: { kind: "client", name: "history_back" } },
  { id: "global.forward", label: "Go Forward",       keys: ["]"], group: "global",
    action: { kind: "client", name: "history_forward" } },
]

// All valid first keys in multi-key sequences
export const PREFIXES: Set<string> = new Set(
  COMMANDS.filter(c => c.keys.length > 1).map(c => c.keys[0])
)
