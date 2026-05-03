export function projectCommands(hook) {
  return [
    {
      id: "list-projects",
      label: "Switch Project...",
      icon: "hero-folder",
      group: "Projects",
      hint: null,
      keywords: ["find", "search", "project", "switch", "open"],
      shortcut: null,
      type: "submenu",
      commands: () => {
        if (!hook) return Promise.resolve([])
        return new Promise((resolve) => {
          hook._paletteProjectsResolve = resolve
          hook.pushEvent("palette:projects", {})
        }).then(projects => projects.map(p => ({
          id: "project-" + p.id,
          label: p.name,
          icon: "hero-folder",
          group: "Projects",
          hint: null,
          keywords: [],
          shortcut: null,
          type: "navigate",
          href: "/projects/" + p.id + "/sessions",
          when: null
        })))
      },
      when: null
    },
  ]
}
