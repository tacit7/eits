export function noteCommands(hook) {
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
    {
      id: "list-notes",
      label: "Find Note...",
      icon: "hero-document-text",
      group: "Notes",
      hint: null,
      keywords: ["find", "search", "open", "note", "memo"],
      shortcut: null,
      type: "submenu",
      commands: () => {
        if (!hook) return Promise.resolve([])
        const projectId = document.getElementById("quick-create-task")?.dataset?.projectId
        return new Promise((resolve) => {
          hook._paletteNotesResolve = resolve
          hook.pushEvent("palette:notes", { project_id: projectId || null })
        }).then(notes => notes.map(n => ({
          id: "note-" + n.id,
          label: n.title || ("Note " + n.id),
          icon: "hero-document-text",
          group: "Notes",
          hint: n.parent_type || null,
          keywords: [],
          shortcut: null,
          type: "navigate",
          href: "/notes/" + n.id + "/edit",
          when: null
        })))
      },
      when: null
    },
  ]
}
