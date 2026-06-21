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
      keywords: ["recent", "activity", "history", "dm", "chat"],
      shortcut: null,
      type: "submenu",
      commands: () => {
        if (!hook) return Promise.resolve([])
        return new Promise((resolve) => {
          hook._paletteRecentSessionsResolve = resolve
          hook.pushEvent("palette:recent-sessions", {})
        }).then(sessions => sessions.map(s => {
          const projectLabel = s.project_name
            ? (s.project_path
                ? `${s.project_name} · ${s.project_path.split("/").pop()}`
                : s.project_name)
            : s.status
          return {
            id: "session-" + s.uuid,
            label: s.name || s.description || (s.uuid || "").slice(0, 8),
            icon: "hero-chat-bubble-left-right",
            group: "Recent",
            hint: projectLabel,
            keywords: [],
            shortcut: null,
            type: "navigate",
            href: "/dm/" + s.uuid,
            when: null
          }
        })))
      },
      when: null
    },
    {
      id: "message-session",
      label: "Message Session...",
      icon: "hero-paper-airplane",
      group: "Workspace",
      hint: null,
      keywords: ["dm", "message", "send", "quick", "chat"],
      shortcut: null,
      type: "submenu",
      commands: () => {
        if (!hook) return Promise.resolve([])
        const projectId = document.getElementById("quick-create-task")?.dataset?.projectId
        return new Promise((resolve) => {
          hook._paletteSessionsResolve = resolve
          hook.pushEvent("palette:sessions", { project_id: projectId || null })
        }).then(sessions => sessions.map(s => ({
          id: "msg-session-" + s.uuid,
          label: s.name || s.description || (s.uuid || "").slice(0, 8),
          icon: "hero-paper-airplane",
          group: projectId ? "Project Sessions" : "Recent",
          hint: s.status,
          keywords: [],
          shortcut: null,
          type: "callback",
          fn: () => {
            document.dispatchEvent(new CustomEvent("vim:quick-dm-compose", {
              detail: { uuid: s.uuid, name: s.name || s.description || "Session" }
            }))
          },
          when: null
        })))
      },
      when: null
    },
  ]
}
