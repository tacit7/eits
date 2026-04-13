export function agentCommands(hook) {
  return [
    {
      id: "create-agent",
      label: "New Agent",
      icon: "hero-cpu-chip",
      group: "Agents",
      hint: null,
      keywords: ["spawn", "run", "claude", "ai", "bot"],
      shortcut: null,
      type: "callback",
      fn: () => { window.dispatchEvent(new CustomEvent("palette:create-agent")) },
      when: null
    },
    {
      id: "update-agent",
      label: "Update Agent Instructions",
      icon: "hero-pencil-square",
      group: "Agents",
      hint: null,
      keywords: ["edit", "modify", "instructions", "agent"],
      shortcut: null,
      type: "callback",
      fn: () => { window.dispatchEvent(new CustomEvent("palette:update-agent")) },
      when: null
    },
    {
      id: "get-agent",
      label: "Get Agent Details",
      icon: "hero-magnifying-glass",
      group: "Agents",
      hint: null,
      keywords: ["find", "search", "lookup", "agent", "uuid", "details"],
      shortcut: null,
      type: "callback",
      fn: () => { window.dispatchEvent(new CustomEvent("palette:get-agent")) },
      when: null
    },
    {
      id: "delete-agent",
      label: "Delete Agent",
      icon: "hero-trash",
      group: "Agents",
      hint: null,
      keywords: ["remove", "delete", "destroy", "agent", "uuid"],
      shortcut: null,
      type: "callback",
      fn: () => { window.dispatchEvent(new CustomEvent("palette:delete-agent")) },
      when: null
    },
    {
      id: "resume-agent",
      label: "Resume Agent",
      icon: "hero-play",
      group: "Agents",
      hint: null,
      keywords: ["resume", "restart", "continue", "spawn", "agent", "uuid"],
      shortcut: null,
      type: "callback",
      fn: () => { window.dispatchEvent(new CustomEvent("palette:resume-agent")) },
      when: null
    },
    {
      id: "list-agents",
      label: "List Agents...",
      icon: "hero-queue-list",
      group: "Agents",
      hint: null,
      keywords: ["view", "show", "all", "agents", "list"],
      shortcut: null,
      type: "submenu",
      commands: () => {
        if (!hook) return Promise.resolve([])
        const projectId = document.getElementById("quick-create-task")?.dataset?.projectId
        return new Promise((resolve) => {
          hook._paletteAgentsResolve = resolve
          hook.pushEvent("palette:list-agents", { project_id: projectId })
          setTimeout(() => resolve([]), 2000)
        }).then(agents => agents.map(a => ({
          id: "agent-" + a.uuid,
          label: a.name,
          icon: "hero-cpu-chip",
          group: null,
          hint: `UUID: ${a.uuid} | Status: ${a.status} | Sessions: ${a.session_count}`,
          keywords: [],
          shortcut: null,
          type: "callback",
          fn: () => {
            navigator.clipboard.writeText(a.uuid)
              .then(() => {
                window.dispatchEvent(new CustomEvent("phx:copy_to_clipboard", {
                  detail: { text: a.uuid, format: "text/plain" }
                }))
              })
          },
          when: null
        })))
      },
      when: null
    },
  ]
}
