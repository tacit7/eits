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
  focus_flyout_after?: boolean
}

export type ClientAction = {
  kind: "client"
  name: "help" | "history_back" | "history_forward" | "command_palette" | "quick_create_note" | "quick_create_task" | "quick_create_chat" | "list_next" | "list_prev" | "list_open" | "list_top" | "list_bottom" | "page_search" | "list_archive" | "list_delete" | "list_yank_uuid" | "list_yank_id" | "focus_composer" | "focus_flyout" | "find_sessions" | "find_recent_sessions" | "find_tasks" | "find_notes" | "find_projects" | "list_group_prev" | "list_group_next" | "list_item_delete" | "list_item_archive" | "list_open_tab" | "session_nav_next" | "session_nav_prev"
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
  { id: "nav.agents",      label: "Go to Agents",      keys: ["g", "a"], group: "navigation",
    action: { kind: "navigate", path: "agents", relative: true } },
  { id: "nav.kanban",     label: "Go to Kanban",      keys: ["g", "k"], group: "navigation",
    action: { kind: "navigate", path: "kanban", relative: true } },
  { id: "nav.keybindings", label: "Keybinding Reference", keys: ["g", "h"], group: "navigation",
    action: { kind: "navigate", path: "/keybindings" } },
  { id: "nav.settings",   label: "Go to Settings",    keys: ["g", ","], group: "navigation",
    action: { kind: "navigate", path: "/settings" } },
  { id: "nav.files",         label: "Go to Files",         keys: ["g", "f"], group: "navigation",
    action: { kind: "navigate", path: "files", relative: true } },
  { id: "nav.prompts",       label: "Go to Prompts",       keys: ["g", "p"], group: "navigation",
    action: { kind: "navigate", path: "prompts", relative: true } },
  { id: "nav.chat",          label: "Go to Chat",          keys: ["g", "c"], group: "navigation",
    action: { kind: "navigate", path: "/chat" } },
  { id: "nav.jobs",          label: "Go to Jobs",          keys: ["g", "j"], group: "navigation",
    action: { kind: "navigate", path: "jobs", relative: true } },
  { id: "nav.usage",         label: "Go to Usage",         keys: ["g", "u"], group: "navigation",
    action: { kind: "navigate", path: "/usage" } },
  { id: "nav.teams",         label: "Go to Teams",         keys: ["g", "m"], group: "navigation",
    action: { kind: "navigate", path: "teams", relative: true } },
  { id: "nav.skills",        label: "Go to Skills",        keys: ["g", "K"], group: "navigation",
    action: { kind: "navigate", path: "skills", relative: true } },
  { id: "nav.notifications", label: "Go to Notifications", keys: ["g", "N"], group: "navigation",
    action: { kind: "navigate", path: "/notifications" } },
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
  { id: "toggle.agents",        label: "Toggle Agents",          keys: ["t", "a"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "agents" }, target: "shell" } },
  { id: "toggle.usage",         label: "Toggle Usage",           keys: ["t", "u"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "usage" }, target: "shell" } },
  { id: "toggle.notifications", label: "Toggle Notifications",   keys: ["t", "b"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "notifications" }, target: "shell" } },
  { id: "toggle.prompts",       label: "Toggle Prompts",         keys: ["t", "P"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "prompts" }, target: "shell" } },

  // t<Upper> — toggle + focus flyout (same event as lowercase, enters flyout focus mode after open)
  { id: "toggle.sessions.focus", label: "Toggle + Focus Sessions", keys: ["t", "S"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "sessions" }, target: "shell", focus_flyout_after: true } },
  { id: "toggle.tasks.focus",    label: "Toggle + Focus Tasks",    keys: ["t", "T"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "tasks" }, target: "shell", focus_flyout_after: true } },
  { id: "toggle.notes.focus",    label: "Toggle + Focus Notes",    keys: ["t", "N"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "notes" }, target: "shell", focus_flyout_after: true } },
  { id: "toggle.files.focus",    label: "Toggle + Focus Files",    keys: ["t", "F"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "files" }, target: "shell", focus_flyout_after: true } },
  { id: "toggle.canvas.focus",   label: "Toggle + Focus Canvas",   keys: ["t", "W"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "canvas" }, target: "shell", focus_flyout_after: true } },
  { id: "toggle.chat.focus",     label: "Toggle + Focus Chat",     keys: ["t", "C"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "chat" }, target: "shell", focus_flyout_after: true } },
  { id: "toggle.skills.focus",   label: "Toggle + Focus Skills",   keys: ["t", "K"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "skills" }, target: "shell", focus_flyout_after: true } },
  { id: "toggle.teams.focus",    label: "Toggle + Focus Teams",    keys: ["t", "M"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "teams" }, target: "shell", focus_flyout_after: true } },
  { id: "toggle.jobs.focus",     label: "Toggle + Focus Jobs",     keys: ["t", "J"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "jobs" }, target: "shell", focus_flyout_after: true } },

  // n — create actions
  { id: "create.agent",   label: "New Agent",   keys: ["n", "a"], group: "create",
    action: { kind: "push_event", event: "toggle_new_session_drawer", payload: {}, target: "shell" } },
  { id: "create.task",    label: "New Task",    keys: ["n", "t"], group: "create",
    action: { kind: "client", name: "quick_create_task" } },
  { id: "create.note",    label: "New Note",    keys: ["n", "n"], group: "create",
    action: { kind: "client", name: "quick_create_note" } },
  { id: "create.chat",    label: "New Chat",    keys: ["n", "c"], group: "create",
    action: { kind: "client", name: "quick_create_chat" } },
  { id: "create.prompt",  label: "New Prompt",  keys: ["n", "p"], group: "create",
    action: { kind: "navigate", path: "prompts/new", relative: true } },
  { id: "create.kanban_task", label: "New Kanban Task", keys: ["n", "k"], group: "create",
    action: { kind: "push_event", event: "toggle_new_task_drawer", payload: {}, target: "active_view" },
    scope: "route_suffix:/kanban" },

  // global
  { id: "global.help",    label: "Keybinding Help",  keys: ["?"], group: "global",
    action: { kind: "client", name: "help" } },
  { id: "global.palette", label: "Command Palette",  keys: [":"], group: "global",
    action: { kind: "client", name: "command_palette" } },
  { id: "global.back",    label: "Go Back",          keys: ["["], group: "global",
    action: { kind: "client", name: "history_back" } },
  { id: "global.forward", label: "Go Forward",       keys: ["]"], group: "global",
    action: { kind: "client", name: "history_forward" } },
  { id: "global.close",   label: "Close Flyout",     keys: ["q"], group: "global",
    action: { kind: "push_event", event: "close_flyout", payload: {}, target: "shell" } },

  // context — page-specific bindings
  { id: "context.filter_drawer", label: "Toggle Filter Drawer", keys: ["f", "f"], group: "context",
    action: { kind: "push_event", event: "toggle_filter_drawer", payload: {}, target: "active_view" },
    scope: "route_suffix:/tasks" },
  { id: "context.agent_drawer",  label: "Toggle Agent Drawer",  keys: ["a", "d"], group: "context",
    action: { kind: "push_event", event: "toggle_agent_drawer", payload: {}, target: "active_view" },
    scope: "route_suffix:/chat" },
  { id: "context.members_panel", label: "Toggle Members Panel", keys: ["m", "b"], group: "context",
    action: { kind: "push_event", event: "toggle_members", payload: {}, target: "active_view" },
    scope: "route_suffix:/chat" },

  // list navigation (context: page with data-vim-list)
  { id: "list.next",   label: "Next item",     keys: ["j"],     group: "context",
    action: { kind: "client", name: "list_next" },   scope: "feature:vim-list" },
  { id: "list.prev",   label: "Previous item", keys: ["k"],     group: "context",
    action: { kind: "client", name: "list_prev" },   scope: "feature:vim-list" },
  { id: "list.open",   label: "Open item",     keys: ["Enter"], group: "context",
    action: { kind: "client", name: "list_open" },   scope: "feature:vim-list" },
  { id: "list.top",    label: "Jump to top",   keys: ["g", "g"], group: "context",
    action: { kind: "client", name: "list_top" },    scope: "feature:vim-list" },
  { id: "list.bottom", label: "Jump to bottom", keys: ["G"],     group: "context",
    action: { kind: "client", name: "list_bottom" }, scope: "feature:vim-list" },
  { id: "global.search", label: "Search",     keys: ["/"],     group: "global",
    action: { kind: "client", name: "page_search" }, scope: "feature:vim-search" },

  // flyout focus (context: flyout is open)
  { id: "flyout.focus", label: "Focus flyout", keys: ["F"], group: "context",
    action: { kind: "client", name: "focus_flyout" }, scope: "feature:vim-flyout" },


  // dm page
  { id: "dm.focus_composer", label: "Focus composer", keys: ["i"], group: "context",
    action: { kind: "client", name: "focus_composer" }, scope: "route_suffix:/dm" },

  // session context actions (sessions page only)
  { id: "session.archive",   label: "Archive session",  keys: ["A"],       group: "context",
    action: { kind: "client", name: "list_archive" },   scope: "page:sessions" },
  { id: "session.delete",    label: "Delete session",   keys: ["D"],       group: "context",
    action: { kind: "client", name: "list_delete" },    scope: "page:sessions" },
  { id: "session.yank_uuid", label: "Copy UUID",        keys: ["y", "u"], group: "context",
    action: { kind: "client", name: "list_yank_uuid" }, scope: "page:sessions" },
  { id: "session.yank_id",   label: "Copy int ID",      keys: ["y", "i"], group: "context",
    action: { kind: "client", name: "list_yank_id" },   scope: "page:sessions" },

  // ── Space leader (Phase A) ──────────────────────────────────────────────────
  // Single-key after Space
  { id: "leader.files",   label: "Toggle Files flyout", keys: ["Space", "e"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "files" }, target: "shell" } },
  { id: "leader.close",   label: "Close flyout",        keys: ["Space", "q"], group: "global",
    action: { kind: "push_event", event: "close_flyout", payload: {}, target: "shell" } },
  { id: "leader.palette", label: "Command palette",     keys: ["Space", ":"], group: "global",
    action: { kind: "client", name: "command_palette" } },
  { id: "leader.help",    label: "Keybinding help",     keys: ["Space", "?"], group: "global",
    action: { kind: "client", name: "help" } },

  // Space s — search
  { id: "leader.search.focus", label: "Focus search", keys: ["Space", "s", "s"], group: "global",
    action: { kind: "client", name: "page_search" }, scope: "feature:vim-search" },

  // Space f — find (picker commands)
  { id: "leader.find.sessions",        label: "Find session",         keys: ["Space", "f", "s"], group: "global",
    action: { kind: "client", name: "find_sessions" } },
  { id: "leader.find.recent_sessions", label: "Find recent session",  keys: ["Space", "f", "r", "s"], group: "global",
    action: { kind: "client", name: "find_recent_sessions" } },
  { id: "leader.find.tasks",           label: "Find task",            keys: ["Space", "f", "t"], group: "global",
    action: { kind: "client", name: "find_tasks" } },
  { id: "leader.find.notes",           label: "Find note",            keys: ["Space", "f", "n"], group: "global",
    action: { kind: "client", name: "find_notes" } },

  // Space p — project picker
  { id: "leader.project.picker", label: "Switch project", keys: ["Space", "p", "p"], group: "global",
    action: { kind: "client", name: "find_projects" } },

  // Space b — buffer/session actions
  { id: "leader.buffer.archive", label: "Archive session", keys: ["Space", "b", "a"], group: "context",
    action: { kind: "client", name: "list_archive" }, scope: "page:sessions" },
  { id: "leader.buffer.delete",  label: "Delete session",  keys: ["Space", "b", "D"], group: "context",
    action: { kind: "client", name: "list_delete" },  scope: "page:sessions" },
  { id: "leader.session.next",   label: "Next session",    keys: ["Space", "b", "n"], group: "navigation",
    action: { kind: "client", name: "session_nav_next" }, scope: "route_suffix:/projects" },
  { id: "leader.session.prev",   label: "Prev session",    keys: ["Space", "b", "p"], group: "navigation",
    action: { kind: "client", name: "session_nav_prev" }, scope: "route_suffix:/projects" },

  // Space x — exit / dismiss
  { id: "leader.exit", label: "Close all flyouts", keys: ["Space", "x", "x"], group: "global",
    action: { kind: "push_event", event: "close_flyout", payload: {}, target: "shell" } },

  // Space g — go to page (aliases of g bindings)
  { id: "leader.nav.sessions",      label: "Go to Sessions",      keys: ["Space", "g", "s"], group: "navigation",
    action: { kind: "navigate", path: "sessions", relative: true } },
  { id: "leader.nav.tasks",         label: "Go to Tasks",         keys: ["Space", "g", "t"], group: "navigation",
    action: { kind: "navigate", path: "tasks", relative: true } },
  { id: "leader.nav.notes",         label: "Go to Notes",         keys: ["Space", "g", "n"], group: "navigation",
    action: { kind: "navigate", path: "notes", relative: true } },
  { id: "leader.nav.agents",        label: "Go to Agents",        keys: ["Space", "g", "a"], group: "navigation",
    action: { kind: "navigate", path: "agents", relative: true } },
  { id: "leader.nav.kanban",        label: "Go to Kanban",        keys: ["Space", "g", "k"], group: "navigation",
    action: { kind: "navigate", path: "kanban", relative: true } },
  { id: "leader.nav.canvas",        label: "Go to Canvas",        keys: ["Space", "g", "w"], group: "navigation",
    action: { kind: "navigate", path: "/canvases" } },
  { id: "leader.nav.files",         label: "Go to Files",         keys: ["Space", "g", "f"], group: "navigation",
    action: { kind: "navigate", path: "files", relative: true } },
  { id: "leader.nav.prompts",       label: "Go to Prompts",       keys: ["Space", "g", "p"], group: "navigation",
    action: { kind: "navigate", path: "prompts", relative: true } },
  { id: "leader.nav.chat",          label: "Go to Chat",          keys: ["Space", "g", "c"], group: "navigation",
    action: { kind: "navigate", path: "/chat" } },
  { id: "leader.nav.jobs",          label: "Go to Jobs",          keys: ["Space", "g", "j"], group: "navigation",
    action: { kind: "navigate", path: "jobs", relative: true } },
  { id: "leader.nav.usage",         label: "Go to Usage",         keys: ["Space", "g", "u"], group: "navigation",
    action: { kind: "navigate", path: "/usage" } },
  { id: "leader.nav.teams",         label: "Go to Teams",         keys: ["Space", "g", "m"], group: "navigation",
    action: { kind: "navigate", path: "teams", relative: true } },
  { id: "leader.nav.skills",        label: "Go to Skills",        keys: ["Space", "g", "K"], group: "navigation",
    action: { kind: "navigate", path: "skills", relative: true } },
  { id: "leader.nav.notifications", label: "Go to Notifications", keys: ["Space", "g", "N"], group: "navigation",
    action: { kind: "navigate", path: "/notifications" } },
  { id: "leader.nav.settings",      label: "Go to Settings",      keys: ["Space", "g", ","], group: "navigation",
    action: { kind: "navigate", path: "/settings" } },
  { id: "leader.nav.keybindings",   label: "Go to Keybindings",   keys: ["Space", "g", "h"], group: "navigation",
    action: { kind: "navigate", path: "/keybindings" } },

  // Space t — toggle rail sections (aliases of t bindings)
  { id: "leader.toggle.sessions",      label: "Toggle Sessions",      keys: ["Space", "t", "s"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "sessions" }, target: "shell" } },
  { id: "leader.toggle.tasks",         label: "Toggle Tasks",         keys: ["Space", "t", "t"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "tasks" }, target: "shell" } },
  { id: "leader.toggle.notes",         label: "Toggle Notes",         keys: ["Space", "t", "n"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "notes" }, target: "shell" } },
  { id: "leader.toggle.files",         label: "Toggle Files",         keys: ["Space", "t", "f"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "files" }, target: "shell" } },
  { id: "leader.toggle.canvas",        label: "Toggle Canvas",        keys: ["Space", "t", "w"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "canvas" }, target: "shell" } },
  { id: "leader.toggle.chat",          label: "Toggle Chat",          keys: ["Space", "t", "c"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "chat" }, target: "shell" } },
  { id: "leader.toggle.skills",        label: "Toggle Skills",        keys: ["Space", "t", "k"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "skills" }, target: "shell" } },
  { id: "leader.toggle.teams",         label: "Toggle Teams",         keys: ["Space", "t", "m"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "teams" }, target: "shell" } },
  { id: "leader.toggle.jobs",          label: "Toggle Jobs",          keys: ["Space", "t", "j"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "jobs" }, target: "shell" } },
  { id: "leader.toggle.agents",        label: "Toggle Agents",        keys: ["Space", "t", "a"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "agents" }, target: "shell" } },
  { id: "leader.toggle.usage",         label: "Toggle Usage",         keys: ["Space", "t", "u"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "usage" }, target: "shell" } },
  { id: "leader.toggle.notifications", label: "Toggle Notifications", keys: ["Space", "t", "b"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "notifications" }, target: "shell" } },
  { id: "leader.toggle.prompts",       label: "Toggle Prompts",       keys: ["Space", "t", "P"], group: "toggle",
    action: { kind: "push_event", event: "toggle_section", payload: { section: "prompts" }, target: "shell" } },
  { id: "leader.toggle.proj_picker",   label: "Toggle Project Picker", keys: ["Space", "t", "p"], group: "toggle",
    action: { kind: "push_event", event: "toggle_proj_picker", payload: {}, target: "shell" } },

  // Space n — create (aliases of n bindings)
  { id: "leader.create.agent",       label: "New Agent",       keys: ["Space", "n", "a"], group: "create",
    action: { kind: "push_event", event: "toggle_new_session_drawer", payload: {}, target: "shell" } },
  { id: "leader.create.task",        label: "New Task",        keys: ["Space", "n", "t"], group: "create",
    action: { kind: "client", name: "quick_create_task" } },
  { id: "leader.create.note",        label: "New Note",        keys: ["Space", "n", "n"], group: "create",
    action: { kind: "client", name: "quick_create_note" } },
  { id: "leader.create.chat",        label: "New Chat",        keys: ["Space", "n", "c"], group: "create",
    action: { kind: "client", name: "quick_create_chat" } },
  { id: "leader.create.prompt",      label: "New Prompt",      keys: ["Space", "n", "p"], group: "create",
    action: { kind: "navigate", path: "prompts/new", relative: true } },
  { id: "leader.create.kanban_task", label: "New Kanban Task", keys: ["Space", "n", "k"], group: "create",
    action: { kind: "push_event", event: "toggle_new_task_drawer", payload: {}, target: "active_view" },
    scope: "route_suffix:/kanban" },

  // group jump (context: any list)
  { id: "list.group_prev", label: "Previous group", keys: ["{"], group: "context",
    action: { kind: "client", name: "list_group_prev" }, scope: "feature:vim-list" },
  { id: "list.group_next", label: "Next group",     keys: ["}"], group: "context",
    action: { kind: "client", name: "list_group_next" }, scope: "feature:vim-list" },

  // generic delete / archive (context: any list)
  { id: "list.delete",  label: "Delete item",  keys: ["d", "d"], group: "context",
    action: { kind: "client", name: "list_item_delete" },  scope: "feature:vim-list" },
  { id: "list.archive", label: "Archive item", keys: ["a", "a"], group: "context",
    action: { kind: "client", name: "list_item_archive" }, scope: "feature:vim-list" },

  // open in new tab (context: any list)
  { id: "list.open_tab", label: "Open in new tab", keys: ["o"], group: "context",
    action: { kind: "client", name: "list_open_tab" }, scope: "feature:vim-list" },
]

// All valid first keys in multi-key sequences
export const PREFIXES: Set<string> = new Set(
  COMMANDS.filter(c => c.keys.length > 1).map(c => c.keys[0])
)
