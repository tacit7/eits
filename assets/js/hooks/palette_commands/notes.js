export function noteCommands(_hook) {
  return [
    {
      id: "create-note",
      label: "Create Note",
      icon: "hero-document-text",
      group: "Notes",
      hint: null,
      keywords: ["new", "add", "write", "memo"],
      shortcut: null,
      type: "callback",
      fn: () => { window.dispatchEvent(new CustomEvent("palette:create-note")) },
      when: null
    },
  ]
}
