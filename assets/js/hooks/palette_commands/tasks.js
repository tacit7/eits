export function taskCommands(hook) {
  return [
    {
      id: "create-task",
      label: "Create Task",
      icon: "hero-plus",
      group: "Tasks",
      hint: null,
      keywords: ["new", "add", "todo"],
      shortcut: null,
      type: "callback",
      fn: () => { window.dispatchEvent(new CustomEvent("palette:create-task")) },
      when: null
    },
    {
      id: "list-tasks",
      label: "Find Task...",
      icon: "hero-check-circle",
      group: "Tasks",
      hint: null,
      keywords: ["find", "search", "open", "task", "todo", "work"],
      shortcut: null,
      type: "submenu",
      commands: () => {
        if (!hook) return Promise.resolve([])
        const projectId = document.getElementById("quick-create-task")?.dataset?.projectId
        return new Promise((resolve) => {
          hook._paletteTasksResolve = resolve
          hook.pushEvent("palette:tasks", { project_id: projectId || null })
        }).then(tasks => tasks.map(t => ({
          id: "task-" + t.id,
          label: t.title || ("Task " + t.id),
          icon: "hero-check-circle",
          group: projectId ? "Project Tasks" : "Tasks",
          hint: t.state_name || null,
          keywords: [],
          shortcut: null,
          type: "navigate",
          href: "/tasks/" + t.id,
          when: null
        })))
      },
      when: null
    },
  ]
}
