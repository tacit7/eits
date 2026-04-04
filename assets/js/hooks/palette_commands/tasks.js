export function taskCommands(_hook) {
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
  ]
}
