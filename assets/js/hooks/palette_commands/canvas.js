export function canvasCommands(hook) {
  return [
    {
      id: "canvas-add-session",
      label: "Add Session to Canvas...",
      icon: "hero-plus-circle",
      group: "Workspace",
      hint: "Add a session window to the current canvas",
      keywords: ["canvas", "add", "attach", "session", "window"],
      shortcut: null,
      type: "submenu",
      when: () => window.location.pathname.startsWith("/canvases/"),
      commands: () => {
        if (!hook) return Promise.resolve([])
        return new Promise((resolve) => {
          hook._paletteSessionsResolve = resolve
          hook.pushEvent("palette:sessions", { project_id: null })
        }).then(sessions => sessions.map(s => ({
          id: "canvas-session-" + s.uuid,
          label: s.name || s.description || (s.uuid || "").slice(0, 8),
          icon: "hero-cpu-chip",
          group: "Sessions",
          hint: s.status,
          keywords: [],
          shortcut: null,
          type: "callback",
          fn: () => {
            window.dispatchEvent(new CustomEvent("canvas:add-session", {
              detail: { sessionId: s.id }
            }))
          }
        })))
      }
    }
  ]
}
