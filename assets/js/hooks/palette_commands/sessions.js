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
  ]
}
