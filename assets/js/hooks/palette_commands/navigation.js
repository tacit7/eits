function currentProjectId() {
  const m = window.location.pathname.match(/^\/projects\/(\d+)(?:\/|$)/)
  return m ? parseInt(m[1], 10) : null
}

function currentProjectCommands(hook) {
  const projectId = currentProjectId()
  if (!projectId) return []

  const projects = JSON.parse(hook?.el?.dataset?.projects || "[]")
  const project = projects.find(p => p.id === projectId)
  if (!project) return []

  const base = `/projects/${projectId}`
  return [
    { id: "cp-sessions", label: "Sessions",      icon: "hero-cpu-chip",               group: "Current Project", hint: project.name, keywords: [],                     shortcut: null, type: "navigate", href: `${base}/sessions`, when: null },
    { id: "cp-tasks",    label: "Tasks",          icon: "hero-clipboard-document-list", group: "Current Project", hint: project.name, keywords: [],                     shortcut: null, type: "navigate", href: `${base}/tasks`,    when: null },
    { id: "cp-kanban",   label: "Kanban",         icon: "hero-view-columns",            group: "Current Project", hint: project.name, keywords: ["board"],              shortcut: null, type: "navigate", href: `${base}/kanban`,   when: null },
    { id: "cp-notes",    label: "Notes",          icon: "hero-document-text",           group: "Current Project", hint: project.name, keywords: [],                     shortcut: null, type: "navigate", href: `${base}/notes`,    when: null },
    { id: "cp-agents",   label: "Agents",         icon: "hero-users",                   group: "Current Project", hint: project.name, keywords: [],                     shortcut: null, type: "navigate", href: `${base}/agents`,   when: null },
    { id: "cp-prompts",  label: "Prompts",        icon: "hero-book-open",               group: "Current Project", hint: project.name, keywords: [],                     shortcut: null, type: "navigate", href: `${base}/prompts`,  when: null },
    { id: "cp-skills",   label: "Skills",         icon: "hero-bolt",                    group: "Current Project", hint: project.name, keywords: [],                     shortcut: null, type: "navigate", href: `${base}/skills`,   when: null },
    { id: "cp-files",    label: "Files",          icon: "hero-folder-open",             group: "Current Project", hint: project.name, keywords: [],                     shortcut: null, type: "navigate", href: `${base}/files`,    when: null },
    { id: "cp-teams",    label: "Teams",          icon: "hero-user-group",              group: "Current Project", hint: project.name, keywords: [],                     shortcut: null, type: "navigate", href: `${base}/teams`,    when: null },
    { id: "cp-config",   label: "Configuration",  icon: "hero-adjustments-horizontal",  group: "Current Project", hint: project.name, keywords: ["settings", "config"], shortcut: null, type: "navigate", href: `${base}/config`,   when: null },
  ]
}

export function navigationCommands(hook) {
  return [
    // --- Current project pages (shown only when inside a project) ---
    ...currentProjectCommands(hook),
    // --- Workspace navigation ---
    { id: "go-sessions",      label: "Sessions",      icon: "hero-cpu-chip",                  group: "Workspace", hint: "Workspace", keywords: [],                        shortcut: null, type: "navigate", href: "/",              when: null },
    { id: "go-tasks",         label: "Tasks",         icon: "hero-clipboard-document-list",   group: "Workspace", hint: "Workspace", keywords: [],                        shortcut: null, type: "navigate", href: "/tasks",          when: null },
    { id: "go-notes",         label: "Notes",         icon: "hero-document-text",             group: "Workspace", hint: "Workspace", keywords: [],                        shortcut: null, type: "navigate", href: "/notes",          when: null },
    // --- Insights navigation ---
    { id: "go-usage",         label: "Usage",         icon: "hero-chart-bar",                 group: "Insights",  hint: "Insights",  keywords: ["analytics", "stats"],    shortcut: null, type: "navigate", href: "/usage",          when: null },
    // --- Knowledge navigation ---
    { id: "go-prompts",       label: "Prompts",       icon: "hero-book-open",                 group: "Knowledge", hint: "Knowledge", keywords: [],                        shortcut: null, type: "navigate", href: "/prompts",        when: null },
    { id: "go-skills",        label: "Skills",        icon: "hero-bolt",                      group: "Knowledge", hint: "Knowledge", keywords: [],                        shortcut: null, type: "navigate", href: "/skills",         when: null },
    { id: "go-notifications", label: "Notifications", icon: "hero-bell",                      group: "Knowledge", hint: "Knowledge", keywords: ["alerts"],                shortcut: null, type: "navigate", href: "/notifications",  when: null },
    // --- System navigation ---
    { id: "go-jobs",          label: "Jobs",          icon: "hero-cog-6-tooth",               group: "System",    hint: "System",    keywords: ["scheduled", "cron"],     shortcut: null, type: "navigate", href: "/jobs",           when: null },
    { id: "go-settings",      label: "Settings",      icon: "hero-adjustments-horizontal",    group: "System",    hint: "System",    keywords: ["config", "preferences"], shortcut: null, type: "navigate", href: "/settings",       when: null },
    // --- Workspace actions ---
    {
      id: "create-chat",
      label: "New Chat",
      icon: "hero-chat-bubble-left-right",
      group: "Workspace",
      hint: null,
      keywords: ["session", "dm", "conversation", "talk"],
      shortcut: null,
      type: "callback",
      fn: () => { window.dispatchEvent(new CustomEvent("palette:create-chat")) },
      when: null
    },
    // --- System actions ---
    {
      id: "toggle-theme",
      label: "Toggle Theme",
      icon: "hero-moon",
      group: "System",
      hint: null,
      keywords: ["dark", "light", "mode"],
      shortcut: null,
      type: "callback",
      fn: () => {
        const current = document.documentElement.getAttribute("data-theme") || localStorage.getItem("theme") || "light"
        const next = current === "dark" ? "light" : "dark"
        localStorage.setItem("theme", next)
        document.documentElement.setAttribute("data-theme", next)
        document.querySelectorAll(".theme-controller").forEach(c => {
          if (c.type === "checkbox") c.checked = next === "dark"
        })
      },
      when: null
    },
    {
      id: "copy-url",
      label: "Copy Current URL",
      icon: "hero-link",
      group: "System",
      hint: null,
      keywords: ["clipboard", "share", "link"],
      shortcut: null,
      type: "callback",
      fn: () => {
        navigator.clipboard.writeText(window.location.href)
          .then(() => {
            window.dispatchEvent(new CustomEvent("phx:copy_to_clipboard", {
              detail: { text: window.location.href, format: "text/plain" }
            }))
          })
          .catch(() => {
            window.dispatchEvent(new CustomEvent("phx:copy_to_clipboard", {
              detail: { text: "", format: "text/plain", error: true }
            }))
          })
      },
      when: null
    },
    // --- Projects submenu ---
    {
      id: "go-project",
      label: "Go to Project...",
      icon: "hero-folder",
      group: "Projects",
      hint: null,
      keywords: ["open", "switch", "navigate"],
      shortcut: null,
      type: "submenu",
      commands: () => {
        const projects = JSON.parse(hook?.el?.dataset?.projects || "[]")
        return projects.map(p => ({
          id: "go-project-" + p.id,
          label: p.name,
          icon: "hero-folder",
          group: "Projects",
          hint: null,
          keywords: [],
          shortcut: null,
          type: "navigate",
          href: "/projects/" + p.id,
          when: null
        }))
      },
      when: null
    },
  ]
}
