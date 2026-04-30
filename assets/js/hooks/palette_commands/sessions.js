export function sessionCommands(hook) {
  return [
    {
      id: "list-sessions",
      label: "Go to Session...",
      icon: "hero-chat-bubble-left-right",
      group: "Workspace",
      hint: null,
      keywords: ["dm", "chat", "open", "history", "recent"],
      shortcut: null,
      type: "submenu",
      commands: () => {
        if (!hook) return Promise.resolve([])
        const projectId = document.getElementById("quick-create-task")?.dataset?.projectId
        return new Promise((resolve) => {
          hook._paletteSessionsResolve = resolve
          hook.pushEvent("palette:sessions", { project_id: projectId || null })
        }).then(sessions => sessions.map(s => ({
          id: "session-" + s.uuid,
          label: s.name || s.description || (s.uuid || "").slice(0, 8),
          icon: "hero-chat-bubble-left-right",
          group: projectId ? "Project Sessions" : "Recent",
          hint: s.status,
          keywords: [],
          shortcut: null,
          type: "navigate",
          href: "/dm/" + s.uuid,
          when: null
        })))
      },
      when: null
    },
    {
      id: "recent-sessions",
      label: "Recent Sessions",
      icon: "hero-clock",
      group: "Workspace",
      hint: null,
      keywords: ["recent", "visited", "history", "dm", "chat"],
      shortcut: null,
      type: "submenu",
      commands: () => {
        try {
          const raw = sessionStorage.getItem("vim-nav:recent-sessions") || "[]"
          const sessions = JSON.parse(raw)
          if (sessions.length === 0) return Promise.resolve([{
            id: "recent-sessions-empty",
            label: "No recently visited sessions",
            icon: "hero-information-circle",
            group: "Recent",
            hint: null, keywords: [], shortcut: null, type: "action",
            action: () => {}, when: null
          }])
          return Promise.resolve(sessions.map(s => ({
            id: "session-" + s.uuid,
            label: s.name || s.uuid.slice(0, 8),
            icon: "hero-chat-bubble-left-right",
            group: "Recent",
            hint: null,
            keywords: [],
            shortcut: null,
            type: "navigate",
            href: "/dm/" + s.uuid,
            when: null
          })))
        } catch {
          return Promise.resolve([])
        }
      },
      when: null
    },
  ]
}
