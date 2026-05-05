import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { isEditableTarget, isCommandActive, keyFromEvent, matchesKnownBindingOrPrefix, VimNav } from "./vim_nav"
import { COMMANDS, PREFIXES } from "./vim_nav_commands"

function makeHook(opts: { enabled?: boolean; projectPath?: string } = {}) {
  const el = document.createElement("div")
  if (opts.enabled !== false) el.dataset.vimNavEnabled = "true"
  if (opts.projectPath) el.dataset.vimProjectPath = opts.projectPath
  document.body.appendChild(el)
  const inst: any = Object.create(VimNav)
  inst.el = el
  inst.pushEvent = vi.fn()
  inst.pushToList = vi.fn()
  inst.handleEvent = vi.fn()
  // Own-property init ensures test isolation — prototype mutable state (buffer, count)
  // can otherwise bleed between tests if a prior test mutates the prototype array.
  inst.buffer = []
  inst.count = 0
  return inst
}

describe("isEditableTarget", () => {
  it("returns true for INPUT", () => {
    const el = document.createElement("input")
    expect(isEditableTarget(el)).toBe(true)
  })

  it("returns true for TEXTAREA", () => {
    const el = document.createElement("textarea")
    expect(isEditableTarget(el)).toBe(true)
  })

  it("returns true for SELECT", () => {
    const el = document.createElement("select")
    expect(isEditableTarget(el)).toBe(true)
  })

  it("returns true for contenteditable", () => {
    const el = document.createElement("div")
    el.setAttribute("contenteditable", "true")
    expect(isEditableTarget(el)).toBe(true)
  })

  it("returns true for role=textbox", () => {
    const el = document.createElement("div")
    el.setAttribute("role", "textbox")
    expect(isEditableTarget(el)).toBe(true)
  })

  it("returns false for a plain div", () => {
    const el = document.createElement("div")
    expect(isEditableTarget(el)).toBe(false)
  })

  it("returns false for null", () => {
    expect(isEditableTarget(null)).toBe(false)
  })
})

describe("keyFromEvent", () => {
  it("preserves case for single character keys", () => {
    expect(keyFromEvent(new KeyboardEvent("keydown", { key: "s" }))).toBe("s")
    expect(keyFromEvent(new KeyboardEvent("keydown", { key: "S" }))).toBe("S")
    expect(keyFromEvent(new KeyboardEvent("keydown", { key: "F" }))).toBe("F")
  })

  it("returns Space for space key", () => {
    const e = new KeyboardEvent("keydown", { key: " " })
    expect(keyFromEvent(e)).toBe("Space")
  })

  it("returns non-character keys unchanged", () => {
    const e = new KeyboardEvent("keydown", { key: "Escape" })
    expect(keyFromEvent(e)).toBe("Escape")
  })

  it("preserves ? (shifted /)", () => {
    const e = new KeyboardEvent("keydown", { key: "?" })
    expect(keyFromEvent(e)).toBe("?")
  })
})

describe("matchesKnownBindingOrPrefix", () => {
  it("matches a known prefix", () => {
    expect(matchesKnownBindingOrPrefix([], "g")).toBe(true)
  })

  it("matches a full two-key sequence", () => {
    expect(matchesKnownBindingOrPrefix(["g"], "s")).toBe(true)
  })

  it("matches a single-key command", () => {
    expect(matchesKnownBindingOrPrefix([], "?")).toBe(true)
  })

  it("returns false for an unknown key", () => {
    expect(matchesKnownBindingOrPrefix([], "x")).toBe(false)
  })

  it("returns false for a bad second key", () => {
    expect(matchesKnownBindingOrPrefix(["g"], "x")).toBe(false)
  })
})

describe("VimNav.buildPath", () => {
  beforeEach(() => { document.body.innerHTML = "" })

  it("returns absolute path unchanged when not relative", () => {
    const h = makeHook()
    expect(h.buildPath("/sessions", false)).toBe("/sessions")
  })

  it("reads project ID from current URL", () => {
    const h = makeHook()
    Object.defineProperty(window, "location", {
      value: { pathname: "/projects/42/sessions" }, configurable: true,
    })
    expect(h.buildPath("tasks", true)).toBe("/projects/42/tasks")
  })

  it("strips leading slash from segment", () => {
    const h = makeHook()
    Object.defineProperty(window, "location", {
      value: { pathname: "/projects/42/sessions" }, configurable: true,
    })
    expect(h.buildPath("/notes", true)).toBe("/projects/42/notes")
  })

  it("returns null for all relative paths when not on a project URL", () => {
    const h = makeHook()
    Object.defineProperty(window, "location", {
      value: { pathname: "/settings" }, configurable: true,
    })
    expect(h.buildPath("tasks", true)).toBeNull()
    expect(h.buildPath("notes", true)).toBeNull()
    expect(h.buildPath("agents", true)).toBeNull()
  })
})

describe("VimNav mode transitions", () => {
  beforeEach(() => { document.body.innerHTML = "" })

  it("focusin on non-editable element does NOT switch to insert", () => {
    const h = makeHook()
    h.mode = "normal"
    h.statusbarEl = document.createElement("div")
    const button = document.createElement("button")
    document.body.appendChild(button)
    h.mounted()
    button.focus()
    button.dispatchEvent(new FocusEvent("focusin", { bubbles: true }))
    expect(h.mode).toBe("normal")
    h.destroyed()
  })

  it("focusin on input switches to insert", () => {
    const h = makeHook()
    h.mounted()
    const input = document.createElement("input")
    document.body.appendChild(input)
    input.focus()
    input.dispatchEvent(new FocusEvent("focusin", { bubbles: true }))
    expect(h.mode).toBe("insert")
    h.destroyed()
  })

  it("Esc on editable in insert mode returns to normal", () => {
    const h = makeHook()
    h.mounted()
    const input = document.createElement("input")
    document.body.appendChild(input)
    input.focus()
    h.setMode("insert")
    h.handleKey(new KeyboardEvent("keydown", { key: "Escape", target: input } as any))
    // jsdom doesn't fully wire target on KeyboardEvent constructor; call directly
    Object.defineProperty(Event.prototype, "target", { configurable: true, get() { return input } })
    const evt = new KeyboardEvent("keydown", { key: "Escape" })
    h.handleKey(evt)
    expect(h.mode).toBe("normal")
    h.destroyed()
  })
})

describe("PREFIXES", () => {
  it("contains g, t, n", () => {
    expect(PREFIXES.has("g")).toBe(true)
    expect(PREFIXES.has("t")).toBe(true)
    expect(PREFIXES.has("n")).toBe(true)
  })

  it("does not contain single-key commands", () => {
    expect(PREFIXES.has("?")).toBe(false)
    expect(PREFIXES.has(":")).toBe(false)
    expect(PREFIXES.has("[")).toBe(false)
    expect(PREFIXES.has("]")).toBe(false)
  })
})

describe("matchesKnownBindingOrPrefix for new prefixes", () => {
  it("matches t prefix", () => expect(matchesKnownBindingOrPrefix([], "t")).toBe(true))
  it("matches n prefix", () => expect(matchesKnownBindingOrPrefix([], "n")).toBe(true))
  it("matches t s sequence", () => expect(matchesKnownBindingOrPrefix(["t"], "s")).toBe(true))
  it("matches n a sequence", () => expect(matchesKnownBindingOrPrefix(["n"], "a")).toBe(true))
  it("matches : command", () => expect(matchesKnownBindingOrPrefix([], ":")).toBe(true))
  it("matches [ command", () => expect(matchesKnownBindingOrPrefix([], "[")).toBe(true))
  it("matches ] command", () => expect(matchesKnownBindingOrPrefix([], "]")).toBe(true))
})

describe("VimNav.executeCommand shell routing", () => {
  beforeEach(() => { document.body.innerHTML = "" })

  it("calls pushEventToShell for target:shell commands", () => {
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    const cmd = COMMANDS.find(c => c.id === "toggle.sessions")!
    h.executeCommand(cmd)
    expect(h.pushEventToShell).toHaveBeenCalledWith("toggle_section", { section: "sessions" })
    expect(h.pushEvent).not.toHaveBeenCalled()
  })

  it("does not call pushEventToShell or pushEvent for navigate commands", () => {
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    const cmd = COMMANDS.find(c => c.id === "nav.sessions")!
    Object.defineProperty(window, "location", {
      value: { href: "", pathname: "/projects/42/sessions" }, configurable: true,
    })
    h.executeCommand(cmd)
    expect(h.pushEventToShell).not.toHaveBeenCalled()
    expect(h.pushEvent).not.toHaveBeenCalled()
  })

  it("n a calls pushEventToShell with toggle_new_session_drawer", () => {
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    const cmd = COMMANDS.find(c => c.id === "create.agent")!
    h.executeCommand(cmd)
    expect(h.pushEventToShell).toHaveBeenCalledWith("toggle_new_session_drawer", {})
    expect(h.pushEvent).not.toHaveBeenCalled()
  })

  it("command_palette dispatches palette:open event", () => {
    const target = document.createElement("div")
    target.id = "command-palette"
    document.body.appendChild(target)
    const listener = vi.fn()
    target.addEventListener("palette:open", listener)
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    const cmd = COMMANDS.find(c => c.id === "global.palette")!
    h.executeCommand(cmd)
    expect(listener).toHaveBeenCalledTimes(1)
  })

  it("n c dispatches palette:create-chat window event", () => {
    const listener = vi.fn()
    window.addEventListener("palette:create-chat", listener)
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    const cmd = COMMANDS.find(c => c.id === "create.chat")!
    h.executeCommand(cmd)
    expect(listener).toHaveBeenCalledTimes(1)
    window.removeEventListener("palette:create-chat", listener)
  })

  it("n n dispatches palette:create-note window event", () => {
    const listener = vi.fn()
    window.addEventListener("palette:create-note", listener)
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    const cmd = COMMANDS.find(c => c.id === "create.note")!
    h.executeCommand(cmd)
    expect(listener).toHaveBeenCalledTimes(1)
    window.removeEventListener("palette:create-note", listener)
  })

  it("n t dispatches palette:create-task window event", () => {
    const listener = vi.fn()
    window.addEventListener("palette:create-task", listener)
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    const cmd = COMMANDS.find(c => c.id === "create.task")!
    h.executeCommand(cmd)
    expect(listener).toHaveBeenCalledTimes(1)
    window.removeEventListener("palette:create-task", listener)
  })

  it("n p command exists with navigate action to prompts/new", () => {
    const cmd = COMMANDS.find(c => c.id === "create.prompt")!
    expect(cmd).toBeDefined()
    expect(cmd.keys).toEqual(["n", "p"])
    expect(cmd.action.kind).toBe("navigate")
    if (cmd.action.kind === "navigate") {
      expect(cmd.action.path).toBe("prompts/new")
      expect(cmd.action.relative).toBe(true)
    }
  })

  it("n k command exists scoped to route_suffix:/kanban", () => {
    const cmd = COMMANDS.find(c => c.id === "create.kanban_task")!
    expect(cmd).toBeDefined()
    expect(cmd.keys).toEqual(["n", "k"])
    expect(cmd.scope).toBe("route_suffix:/kanban")
    expect(cmd.action.kind).toBe("push_event")
    if (cmd.action.kind === "push_event") {
      expect(cmd.action.event).toBe("toggle_new_task_drawer")
      expect(cmd.action.target).toBe("active_view")
    }
  })

  it("isCommandActive returns true for n k when pathname includes /kanban", () => {
    Object.defineProperty(window, "location", {
      value: { pathname: "/projects/1/kanban" },
      writable: true,
      configurable: true,
    })
    const cmd = COMMANDS.find(c => c.id === "create.kanban_task")!
    const result = isCommandActive(cmd)
    Object.defineProperty(window, "location", {
      value: { pathname: "/" },
      writable: true,
      configurable: true,
    })
    expect(result).toBe(true)
  })

  it("isCommandActive returns false for n k when pathname is /tasks", () => {
    Object.defineProperty(window, "location", {
      value: { pathname: "/projects/1/tasks" },
      writable: true,
      configurable: true,
    })
    const cmd = COMMANDS.find(c => c.id === "create.kanban_task")!
    const result = isCommandActive(cmd)
    Object.defineProperty(window, "location", {
      value: { pathname: "/" },
      writable: true,
      configurable: true,
    })
    expect(result).toBe(false)
  })

  it("q calls pushEventToShell with close_flyout", () => {
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    const cmd = COMMANDS.find(c => c.id === "global.close")!
    h.executeCommand(cmd)
    expect(h.pushEventToShell).toHaveBeenCalledWith("close_flyout", {})
  })
})

describe("VimNav which-key overlay", () => {
  beforeEach(() => {
    vi.useFakeTimers()
    document.body.innerHTML = ""
  })
  afterEach(() => {
    vi.useRealTimers()
    document.body.innerHTML = ""
  })

  it("showWhichKey renders overlay after 300ms", () => {
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    h.showWhichKey(["t"])
    expect(document.getElementById("vim-nav-which-key")).toBeNull()
    vi.advanceTimersByTime(300)
    expect(document.getElementById("vim-nav-which-key")).not.toBeNull()
    h.hideWhichKey()
  })

  it("hideWhichKey before 300ms cancels the timer (no overlay appears)", () => {
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    h.showWhichKey(["t"])
    h.hideWhichKey()
    vi.advanceTimersByTime(300)
    expect(document.getElementById("vim-nav-which-key")).toBeNull()
  })

  it("hideWhichKey removes DOM element if overlay was rendered", () => {
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    h.showWhichKey(["t"])
    vi.advanceTimersByTime(300)
    expect(document.getElementById("vim-nav-which-key")).not.toBeNull()
    h.hideWhichKey()
    expect(document.getElementById("vim-nav-which-key")).toBeNull()
  })

  it("second showWhichKey call resets the timer", () => {
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    h.showWhichKey(["t"])
    vi.advanceTimersByTime(200)
    h.showWhichKey(["n"])
    vi.advanceTimersByTime(100)  // only 100ms since second call — should not render yet
    expect(document.getElementById("vim-nav-which-key")).toBeNull()
    vi.advanceTimersByTime(200)  // 300ms since second call — should render
    expect(document.getElementById("vim-nav-which-key")).not.toBeNull()
    h.hideWhichKey()
  })

  it("clearSequence hides which-key", () => {
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    h.showWhichKey(["g"])
    vi.advanceTimersByTime(300)
    expect(document.getElementById("vim-nav-which-key")).not.toBeNull()
    h.clearSequence()
    expect(document.getElementById("vim-nav-which-key")).toBeNull()
  })
})

describe("VimNav list navigation (j/k/Enter)", () => {
  beforeEach(() => { document.body.innerHTML = "" })

  function makeList(itemCount: number): HTMLElement {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    for (let i = 0; i < itemCount; i++) {
      const item = document.createElement("li")
      item.setAttribute("data-vim-list-item", "")
      item.textContent = `Item ${i}`
      list.appendChild(item)
    }
    document.body.appendChild(list)
    return list
  }

  it("j increments listFocusIndex and applies vim-nav-focused class", () => {
    makeList(3)
    const h = makeHook()
    h.listFocusIndex = -1
    const cmd = COMMANDS.find(c => c.id === "list.next")!
    h.executeCommand(cmd)
    expect(h.listFocusIndex).toBe(0)
    const items = document.querySelectorAll("[data-vim-list-item]")
    expect(items[0].classList.contains("vim-nav-focused")).toBe(true)
  })

  it("j clamps at last item when already at end", () => {
    makeList(2)
    const h = makeHook()
    h.listFocusIndex = 1
    const cmd = COMMANDS.find(c => c.id === "list.next")!
    h.executeCommand(cmd)
    expect(h.listFocusIndex).toBe(1)
  })

  it("k decrements listFocusIndex", () => {
    makeList(3)
    const h = makeHook()
    h.listFocusIndex = 2
    const cmd = COMMANDS.find(c => c.id === "list.prev")!
    h.executeCommand(cmd)
    expect(h.listFocusIndex).toBe(1)
    const items = document.querySelectorAll("[data-vim-list-item]")
    expect(items[1].classList.contains("vim-nav-focused")).toBe(true)
  })

  it("k clamps at 0 when already at first item", () => {
    makeList(3)
    const h = makeHook()
    h.listFocusIndex = 0
    const cmd = COMMANDS.find(c => c.id === "list.prev")!
    h.executeCommand(cmd)
    expect(h.listFocusIndex).toBe(0)
  })

  it("Enter dispatches click on the focused list item", () => {
    makeList(3)
    const h = makeHook()
    h.listFocusIndex = 1
    const items = document.querySelectorAll("[data-vim-list-item]")
    const clickSpy = vi.fn()
    items[1].addEventListener("click", clickSpy)
    const cmd = COMMANDS.find(c => c.id === "list.open")!
    h.executeCommand(cmd)
    expect(clickSpy).toHaveBeenCalledTimes(1)
  })

  it("Enter is a no-op when listFocusIndex is -1", () => {
    makeList(3)
    const h = makeHook()
    h.listFocusIndex = -1
    const cmd = COMMANDS.find(c => c.id === "list.open")!
    expect(() => h.executeCommand(cmd)).not.toThrow()
  })

  it("j on page without data-vim-list is a no-op and does not throw", () => {
    // no list in DOM
    const h = makeHook()
    h.listFocusIndex = -1
    const cmd = COMMANDS.find(c => c.id === "list.next")!
    expect(() => h.executeCommand(cmd)).not.toThrow()
    expect(h.listFocusIndex).toBe(-1)
  })

  it("clearListFocus resets index and removes vim-nav-focused from all items", () => {
    makeList(3)
    const h = makeHook()
    h.listFocusIndex = 1
    h.focusListItem(1)
    const items = document.querySelectorAll("[data-vim-list-item]")
    expect(items[1].classList.contains("vim-nav-focused")).toBe(true)
    h.clearListFocus()
    expect(h.listFocusIndex).toBe(-1)
    items.forEach(el => expect(el.classList.contains("vim-nav-focused")).toBe(false))
  })

  function makeSessionList(count: number): HTMLElement {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    for (let i = 0; i < count; i++) {
      const item = document.createElement("li")
      item.setAttribute("data-vim-list-item", "")
      item.setAttribute("data-session-id", String(i + 1))
      item.textContent = `Session ${i + 1}`
      list.appendChild(item)
    }
    document.body.appendChild(list)
    return list
  }

  function withSessionsScope(fn: () => void) {
    const marker = document.createElement("div")
    marker.setAttribute("data-vim-page", "sessions")
    document.body.appendChild(marker)
    try { fn() } finally { marker.remove() }
  }

  it("archive refocuses next item when middle item is removed", async () => {
    const list = makeSessionList(4)
    const h = makeHook()
    h.pushToList = vi.fn()
    h.listFocusIndex = 1
    h.focusListItem(1)

    withSessionsScope(() => {
      const cmd = COMMANDS.find(c => c.id === "session.archive")!
      h.executeCommand(cmd)
      expect(h.pushToList).toHaveBeenCalledWith("archive_session", { session_id: "2" })
    })

    // Simulate LiveView removing the archived row
    list.children[1].remove()
    await new Promise(r => setTimeout(r, 0))

    // Should now focus index 1 (next item, formerly at index 2)
    expect(h.listFocusIndex).toBe(1)
    const items = document.querySelectorAll("[data-vim-list-item]")
    expect(items[1].classList.contains("vim-nav-focused")).toBe(true)
  })

  it("archive clamps to last item when the last item is archived", async () => {
    const list = makeSessionList(3)
    const h = makeHook()
    h.pushToList = vi.fn()
    h.listFocusIndex = 2
    h.focusListItem(2)

    withSessionsScope(() => {
      const cmd = COMMANDS.find(c => c.id === "session.archive")!
      h.executeCommand(cmd)
    })

    // Simulate LiveView removing the last row
    list.children[2].remove()
    await new Promise(r => setTimeout(r, 0))

    // Should clamp to index 1 (new last item)
    expect(h.listFocusIndex).toBe(1)
    const items = document.querySelectorAll("[data-vim-list-item]")
    expect(items[1].classList.contains("vim-nav-focused")).toBe(true)
  })

  it("archive sets listFocusIndex to -1 when last item removed", async () => {
    const list = makeSessionList(1)
    const h = makeHook()
    h.pushToList = vi.fn()
    h.listFocusIndex = 0
    h.focusListItem(0)

    withSessionsScope(() => {
      const cmd = COMMANDS.find(c => c.id === "session.archive")!
      h.executeCommand(cmd)
    })

    list.children[0].remove()
    await new Promise(r => setTimeout(r, 0))

    expect(h.listFocusIndex).toBe(-1)
  })
})

describe("VimNav page search (/)", () => {
  beforeEach(() => { document.body.innerHTML = "" })

  it("/ focuses the element with data-vim-search", () => {
    const input = document.createElement("input")
    input.setAttribute("data-vim-search", "")
    document.body.appendChild(input)
    const focusSpy = vi.spyOn(input, "focus")
    const h = makeHook()
    const cmd = COMMANDS.find(c => c.id === "global.search")!
    h.executeCommand(cmd)
    expect(focusSpy).toHaveBeenCalledTimes(1)
  })

  it("/ is a no-op when no data-vim-search element exists", () => {
    const h = makeHook()
    const cmd = COMMANDS.find(c => c.id === "global.search")!
    expect(() => h.executeCommand(cmd)).not.toThrow()
  })
})

describe("isCommandActive scope gating", () => {
  beforeEach(() => { document.body.innerHTML = "" })

  it("returns true for commands with no scope", () => {
    const cmd = COMMANDS.find(c => c.id === "nav.sessions")!
    expect(isCommandActive(cmd)).toBe(true)
  })

  it("returns false for feature:vim-list when no data-vim-list in DOM", () => {
    const cmd = COMMANDS.find(c => c.id === "list.next")!
    expect(isCommandActive(cmd)).toBe(false)
  })

  it("returns true for feature:vim-list when data-vim-list exists", () => {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    document.body.appendChild(list)
    const cmd = COMMANDS.find(c => c.id === "list.next")!
    expect(isCommandActive(cmd)).toBe(true)
  })

  it("returns false for feature:vim-search when no data-vim-search in DOM", () => {
    const cmd = COMMANDS.find(c => c.id === "global.search")!
    expect(isCommandActive(cmd)).toBe(false)
  })

  it("returns true for feature:vim-search when data-vim-search exists", () => {
    const input = document.createElement("input")
    input.setAttribute("data-vim-search", "")
    document.body.appendChild(input)
    const cmd = COMMANDS.find(c => c.id === "global.search")!
    expect(isCommandActive(cmd)).toBe(true)
  })
})

describe("matchesKnownBindingOrPrefix respects scope", () => {
  beforeEach(() => { document.body.innerHTML = "" })

  it("returns false for j when no data-vim-list", () => {
    expect(matchesKnownBindingOrPrefix([], "j")).toBe(false)
  })

  it("returns true for j when data-vim-list exists", () => {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    document.body.appendChild(list)
    expect(matchesKnownBindingOrPrefix([], "j")).toBe(true)
  })

  it("returns false for / when no data-vim-search", () => {
    expect(matchesKnownBindingOrPrefix([], "/")).toBe(false)
  })

  it("returns true for / when data-vim-search exists", () => {
    const input = document.createElement("input")
    input.setAttribute("data-vim-search", "")
    document.body.appendChild(input)
    expect(matchesKnownBindingOrPrefix([], "/")).toBe(true)
  })

  it("global commands still match without scope elements", () => {
    expect(matchesKnownBindingOrPrefix([], "?")).toBe(true)
    expect(matchesKnownBindingOrPrefix([], "g")).toBe(true)
  })
})

describe("VimNav.handleKey does NOT preventDefault on inactive scope keys", () => {
  beforeEach(() => { document.body.innerHTML = "" })

  it("j on page without data-vim-list does NOT call preventDefault", () => {
    const h = makeHook()
    h.mode = "normal"
    const evt = new KeyboardEvent("keydown", { key: "j" })
    Object.defineProperty(evt, "target", { value: document.body, configurable: true })
    const spy = vi.spyOn(evt, "preventDefault")
    h.handleKey(evt)
    expect(spy).not.toHaveBeenCalled()
    expect(h.buffer).toEqual([])
  })

  it("/ on page without data-vim-search does NOT call preventDefault", () => {
    const h = makeHook()
    h.mode = "normal"
    const evt = new KeyboardEvent("keydown", { key: "/" })
    Object.defineProperty(evt, "target", { value: document.body, configurable: true })
    const spy = vi.spyOn(evt, "preventDefault")
    h.handleKey(evt)
    expect(spy).not.toHaveBeenCalled()
    expect(h.buffer).toEqual([])
  })

  it("k on page without data-vim-list does NOT call preventDefault", () => {
    const h = makeHook()
    h.mode = "normal"
    const evt = new KeyboardEvent("keydown", { key: "k" })
    Object.defineProperty(evt, "target", { value: document.body, configurable: true })
    const spy = vi.spyOn(evt, "preventDefault")
    h.handleKey(evt)
    expect(spy).not.toHaveBeenCalled()
  })

  it("Enter on page without data-vim-list does NOT call preventDefault", () => {
    const h = makeHook()
    h.mode = "normal"
    const evt = new KeyboardEvent("keydown", { key: "Enter" })
    Object.defineProperty(evt, "target", { value: document.body, configurable: true })
    const spy = vi.spyOn(evt, "preventDefault")
    h.handleKey(evt)
    expect(spy).not.toHaveBeenCalled()
  })

  it("j on page WITH data-vim-list DOES call preventDefault", () => {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    const item = document.createElement("li")
    item.setAttribute("data-vim-list-item", "")
    list.appendChild(item)
    document.body.appendChild(list)
    const h = makeHook()
    h.mode = "normal"
    const evt = new KeyboardEvent("keydown", { key: "j" })
    Object.defineProperty(evt, "target", { value: document.body, configurable: true })
    const spy = vi.spyOn(evt, "preventDefault")
    h.handleKey(evt)
    expect(spy).toHaveBeenCalled()
  })
})

describe("VimNav showHelp scope filtering", () => {
  beforeEach(() => {
    vi.useFakeTimers()
    document.body.innerHTML = ""
  })
  afterEach(() => {
    vi.useRealTimers()
    document.body.innerHTML = ""
  })

  function getHelpText(): string {
    const overlay = document.getElementById("vim-nav-help")
    return overlay?.textContent ?? ""
  }

  it("? overlay does NOT show Next item / Previous item / Open item on page without data-vim-list", () => {
    const h = makeHook()
    h.showHelp()
    const text = getHelpText()
    expect(text).not.toContain("Next item")
    expect(text).not.toContain("Previous item")
    expect(text).not.toContain("Open item")
    h.hideHelp()
  })

  it("? overlay DOES show Next item / Previous item / Open item on page with data-vim-list", () => {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    document.body.appendChild(list)
    const h = makeHook()
    h.showHelp()
    const text = getHelpText()
    expect(text).toContain("Next item")
    expect(text).toContain("Previous item")
    expect(text).toContain("Open item")
    h.hideHelp()
  })

  it("? overlay does NOT show Search on page without data-vim-search", () => {
    const h = makeHook()
    h.showHelp()
    const text = getHelpText()
    expect(text).not.toContain("Search")
    h.hideHelp()
  })

  it("? overlay DOES show Search on page with data-vim-search", () => {
    const input = document.createElement("input")
    input.setAttribute("data-vim-search", "")
    document.body.appendChild(input)
    const h = makeHook()
    h.showHelp()
    const text = getHelpText()
    expect(text).toContain("Search")
    h.hideHelp()
  })

  it("? overlay skips Context group header when no data-vim-list on page", () => {
    const h = makeHook()
    h.showHelp()
    const text = getHelpText()
    expect(text).not.toContain("Context")
    h.hideHelp()
  })

  it("? overlay includes Context group header when data-vim-list is present", () => {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    document.body.appendChild(list)
    const h = makeHook()
    h.showHelp()
    const text = getHelpText()
    expect(text).toContain("Context")
    h.hideHelp()
  })
})

describe("VimNav _renderWhichKey scope filtering", () => {
  beforeEach(() => {
    vi.useFakeTimers()
    document.body.innerHTML = ""
  })
  afterEach(() => {
    vi.useRealTimers()
    document.body.innerHTML = ""
  })

  it("which-key does not render overlay when all prefix commands are inactive", () => {
    // There are no two-key commands with scoped keys by default, but we can
    // verify that a prefix with no active matching commands produces no overlay.
    // Use a made-up prefix that has no commands at all (already returns early).
    const h = makeHook()
    h._renderWhichKey(["z"])
    expect(document.getElementById("vim-nav-which-key")).toBeNull()
  })

  it("which-key renders overlay for active prefix commands", () => {
    const h = makeHook()
    h._renderWhichKey(["g"])
    expect(document.getElementById("vim-nav-which-key")).not.toBeNull()
    h.hideWhichKey()
  })

  it("which-key renders overlay for Space prefix with all commands as second level", () => {
    const h = makeHook()
    h._renderWhichKey(["Space"])
    const overlay = document.getElementById("vim-nav-which-key")
    expect(overlay).not.toBeNull()
    expect(overlay!.textContent).toContain("Space →")
    h.hideWhichKey()
  })

  it("which-key renders overlay for Space g as third-level prefix", () => {
    const h = makeHook()
    h._renderWhichKey(["Space", "g"])
    const overlay = document.getElementById("vim-nav-which-key")
    expect(overlay).not.toBeNull()
    expect(overlay!.textContent).toContain("Space g →")
    expect(overlay!.textContent).toContain("Go to Sessions")
    h.hideWhichKey()
  })

  it("which-key header shows full prefix sequence joined by space", () => {
    const h = makeHook()
    h._renderWhichKey(["Space", "t"])
    const overlay = document.getElementById("vim-nav-which-key")
    expect(overlay!.textContent).toContain("Space t →")
    h.hideWhichKey()
  })

  it("Space which-key shows sub-group entries with + prefix for g t n", () => {
    const h = makeHook()
    h._renderWhichKey(["Space"])
    const overlay = document.getElementById("vim-nav-which-key")!
    const text = overlay.textContent!
    // sub-group labels
    expect(text).toContain("+go to page")
    expect(text).toContain("+toggle rail")
    expect(text).toContain("+create")
    h.hideWhichKey()
  })

  it("Space which-key shows direct actions without + prefix", () => {
    const h = makeHook()
    h._renderWhichKey(["Space"])
    const overlay = document.getElementById("vim-nav-which-key")!
    const text = overlay.textContent!
    expect(text).toContain("Toggle Files flyout")
    expect(text).toContain("Command palette")
    expect(text).toContain("Close flyout")
    h.hideWhichKey()
  })

  it("g which-key shows direct navigation labels (no + prefix)", () => {
    const h = makeHook()
    h._renderWhichKey(["g"])
    const overlay = document.getElementById("vim-nav-which-key")!
    const text = overlay.textContent!
    expect(text).toContain("Go to Sessions")
    expect(text).toContain("Go to Tasks")
    expect(text).not.toContain("+go to page")
    h.hideWhichKey()
  })
})

describe("Space leader", () => {
  beforeEach(() => {
    vi.useFakeTimers()
    document.body.innerHTML = ""
  })
  afterEach(() => {
    vi.useRealTimers()
    document.body.innerHTML = ""
  })

  it("Space is in PREFIXES", () => {
    expect(PREFIXES.has("Space")).toBe(true)
  })

  it("Space key is accepted by matchesKnownBindingOrPrefix", () => {
    expect(matchesKnownBindingOrPrefix([], "Space")).toBe(true)
  })

  it("showWhichKey with Space prefix uses 0ms delay", () => {
    const h = makeHook()
    h.showWhichKey(["Space"], 0)
    // With 0ms delay, overlay renders immediately after advancing 0ms
    vi.advanceTimersByTime(0)
    expect(document.getElementById("vim-nav-which-key")).not.toBeNull()
    h.hideWhichKey()
  })

  it("resetSequenceTimer uses 2000ms for Space sequences", () => {
    const h = makeHook()
    h.buffer = ["Space"]
    h.resetSequenceTimer()
    vi.advanceTimersByTime(1999)
    expect(h.buffer).toEqual(["Space"])
    vi.advanceTimersByTime(1)
    expect(h.buffer).toEqual([])
  })

  it("resetSequenceTimer uses 1000ms for non-Space sequences", () => {
    const h = makeHook()
    h.buffer = ["g"]
    h.resetSequenceTimer()
    vi.advanceTimersByTime(999)
    expect(h.buffer).toEqual(["g"])
    vi.advanceTimersByTime(1)
    expect(h.buffer).toEqual([])
  })

  it("Space e calls pushEventToShell with toggle_section files", () => {
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    const cmd = COMMANDS.find(c => c.id === "leader.files")!
    expect(cmd).toBeDefined()
    h.executeCommand(cmd)
    expect(h.pushEventToShell).toHaveBeenCalledWith("toggle_section", { section: "files" })
  })

  it("Space : opens command palette", () => {
    const target = document.createElement("div")
    target.id = "command-palette"
    document.body.appendChild(target)
    const listener = vi.fn()
    target.addEventListener("palette:open", listener)
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    const cmd = COMMANDS.find(c => c.id === "leader.palette")!
    h.executeCommand(cmd)
    expect(listener).toHaveBeenCalledTimes(1)
  })

  it("Space ? shows help overlay", () => {
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    const cmd = COMMANDS.find(c => c.id === "leader.help")!
    h.executeCommand(cmd)
    expect(document.getElementById("vim-nav-help")).not.toBeNull()
    h.hideHelp()
  })

  it("Space g s command exists with navigate action", () => {
    const cmd = COMMANDS.find(c => c.id === "leader.nav.sessions")!
    expect(cmd).toBeDefined()
    expect(cmd.keys).toEqual(["Space", "g", "s"])
    expect(cmd.action.kind).toBe("navigate")
  })

  it("Space t s command exists with push_event toggle_section sessions", () => {
    const cmd = COMMANDS.find(c => c.id === "leader.toggle.sessions")!
    expect(cmd).toBeDefined()
    expect(cmd.keys).toEqual(["Space", "t", "s"])
    if (cmd.action.kind === "push_event") {
      expect(cmd.action.event).toBe("toggle_section")
      expect((cmd.action.payload as any).section).toBe("sessions")
    }
  })

  it("Space n a command exists mirroring create.agent", () => {
    const cmd = COMMANDS.find(c => c.id === "leader.create.agent")!
    expect(cmd).toBeDefined()
    expect(cmd.keys).toEqual(["Space", "n", "a"])
    if (cmd.action.kind === "push_event") {
      expect(cmd.action.event).toBe("toggle_new_session_drawer")
    }
  })

  it("Space b a archives session (page:sessions scope)", () => {
    const cmd = COMMANDS.find(c => c.id === "leader.buffer.archive")!
    expect(cmd).toBeDefined()
    expect(cmd.scope).toBe("page:sessions")
    expect(cmd.action.kind).toBe("client")
    if (cmd.action.kind === "client") expect(cmd.action.name).toBe("list_archive")
  })

  it("Space b n navigates to next session (route_suffix:/projects scope)", () => {
    const cmd = COMMANDS.find(c => c.id === "leader.session.next")!
    expect(cmd).toBeDefined()
    expect(cmd.label).toBe("Next session")
    expect(cmd.keys).toEqual(["Space", "b", "n"])
    expect(cmd.group).toBe("navigation")
    expect(cmd.scope).toBe("route_suffix:/projects")
    expect(cmd.action.kind).toBe("client")
    if (cmd.action.kind === "client") expect(cmd.action.name).toBe("session_nav_next")
  })

  it("Space b p navigates to previous session (route_suffix:/projects scope)", () => {
    const cmd = COMMANDS.find(c => c.id === "leader.session.prev")!
    expect(cmd).toBeDefined()
    expect(cmd.label).toBe("Prev session")
    expect(cmd.keys).toEqual(["Space", "b", "p"])
    expect(cmd.group).toBe("navigation")
    expect(cmd.scope).toBe("route_suffix:/projects")
    expect(cmd.action.kind).toBe("client")
    if (cmd.action.kind === "client") expect(cmd.action.name).toBe("session_nav_prev")
  })

  it("Space x x fires close_flyout", () => {
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    const cmd = COMMANDS.find(c => c.id === "leader.exit")!
    h.executeCommand(cmd)
    expect(h.pushEventToShell).toHaveBeenCalledWith("close_flyout", {})
  })

  it("all 16 Space g nav commands exist", () => {
    const ids = ["s","t","n","a","k","w","f","p","c","j","u","m","K","N",",","h"]
    for (const id of ids) {
      const cmd = COMMANDS.find(c => c.id === `leader.nav.${id === "," ? "settings" : id === "h" ? "keybindings" : id === "K" ? "skills" : id === "N" ? "notifications" : id === "m" ? "teams" : id === "u" ? "usage" : id === "j" ? "jobs" : id === "c" ? "chat" : id === "p" ? "prompts" : id === "f" ? "files" : id === "w" ? "canvas" : id === "k" ? "kanban" : id === "a" ? "agents" : id === "n" ? "notes" : id === "t" ? "tasks" : "sessions"}`)
      expect(cmd, `leader.nav.* for key ${id}`).toBeDefined()
      expect(cmd!.keys[1]).toBe("g")
      expect(cmd!.keys[2]).toBe(id)
    }
  })
})

describe("context bindings", () => {
  it("f f is a prefix when route includes /tasks", () => {
    Object.defineProperty(window, "location", {
      value: { pathname: "/projects/1/tasks" },
      writable: true,
      configurable: true,
    })
    expect(matchesKnownBindingOrPrefix([], "f")).toBe(true)
  })

  it("f f is NOT active on non-tasks route", () => {
    Object.defineProperty(window, "location", {
      value: { pathname: "/projects/1/notes" },
      writable: true,
      configurable: true,
    })
    expect(matchesKnownBindingOrPrefix([], "f")).toBe(false)
  })

  it("a d is active on /chat route", () => {
    Object.defineProperty(window, "location", {
      value: { pathname: "/projects/1/chat" },
      writable: true,
      configurable: true,
    })
    expect(matchesKnownBindingOrPrefix([], "a")).toBe(true)
    expect(matchesKnownBindingOrPrefix(["a"], "d")).toBe(true)
  })

  it("m b is active on /chat route", () => {
    Object.defineProperty(window, "location", {
      value: { pathname: "/projects/1/chat" },
      writable: true,
      configurable: true,
    })
    expect(matchesKnownBindingOrPrefix([], "m")).toBe(true)
    expect(matchesKnownBindingOrPrefix(["m"], "b")).toBe(true)
  })

  it("isCommandActive returns true for route_suffix:/tasks when pathname includes /tasks", () => {
    Object.defineProperty(window, "location", {
      value: { pathname: "/projects/1/tasks" },
      writable: true,
      configurable: true,
    })
    const cmd = COMMANDS.find(c => c.id === "context.filter_drawer")!
    expect(isCommandActive(cmd)).toBe(true)
  })

  it("isCommandActive returns false for route_suffix:/tasks when pathname is /chat", () => {
    Object.defineProperty(window, "location", {
      value: { pathname: "/projects/1/chat" },
      writable: true,
      configurable: true,
    })
    const cmd = COMMANDS.find(c => c.id === "context.filter_drawer")!
    expect(isCommandActive(cmd)).toBe(false)
  })
})

describe("dm.focus_composer (i on /dm route)", () => {
  beforeEach(() => {
    document.body.innerHTML = ""
  })
  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("command is registered with key i and scope route_suffix:/dm", () => {
    const cmd = COMMANDS.find(c => c.id === "dm.focus_composer")!
    expect(cmd).toBeTruthy()
    expect(cmd.keys).toEqual(["i"])
    expect(cmd.scope).toBe("route_suffix:/dm")
    expect(cmd.action).toEqual({ kind: "client", name: "focus_composer" })
  })

  it("isCommandActive true on /dm path, false elsewhere", () => {
    const cmd = COMMANDS.find(c => c.id === "dm.focus_composer")!
    Object.defineProperty(window, "location", {
      value: { pathname: "/projects/1/dm" }, writable: true, configurable: true,
    })
    expect(isCommandActive(cmd)).toBe(true)
    Object.defineProperty(window, "location", {
      value: { pathname: "/projects/1/sessions" }, writable: true, configurable: true,
    })
    expect(isCommandActive(cmd)).toBe(false)
  })

  it("focus_composer action focuses the [data-vim-composer] element", () => {
    const composer = document.createElement("textarea")
    composer.setAttribute("data-vim-composer", "")
    document.body.appendChild(composer)
    const focusSpy = vi.spyOn(composer, "focus")
    const h = makeHook()
    h.executeCommand(COMMANDS.find(c => c.id === "dm.focus_composer")!)
    expect(focusSpy).toHaveBeenCalledTimes(1)
  })

  it("focus_composer is a no-op when [data-vim-composer] is missing", () => {
    const h = makeHook()
    expect(() =>
      h.executeCommand(COMMANDS.find(c => c.id === "dm.focus_composer")!)
    ).not.toThrow()
  })
})

describe("flyout focus mode", () => {
  beforeEach(() => {
    document.body.innerHTML = ""
  })
  afterEach(() => {
    document.body.innerHTML = ""
  })

  function setupFlyout(open: boolean, itemCount = 3): HTMLElement[] {
    const panel = document.createElement("div")
    panel.setAttribute("data-flyout-panel", "")
    panel.setAttribute("data-vim-flyout-open", String(open))
    const items: HTMLElement[] = []
    for (let i = 0; i < itemCount; i++) {
      const a = document.createElement("a")
      a.setAttribute("data-vim-flyout-item", "")
      a.textContent = `flyout-${i}`
      panel.appendChild(a)
      items.push(a)
    }
    document.body.appendChild(panel)
    return items
  }

  it("feature:vim-flyout scope is active only when flyout is open", () => {
    const cmd = COMMANDS.find(c => c.id === "flyout.focus")!
    expect(isCommandActive(cmd)).toBe(false)
    setupFlyout(true)
    expect(isCommandActive(cmd)).toBe(true)
  })

  it("feature:vim-list scope is active when flyout is open even without [data-vim-list]", () => {
    const cmd = COMMANDS.find(c => c.id === "list.next")!
    expect(isCommandActive(cmd)).toBe(false)
    setupFlyout(true)
    expect(isCommandActive(cmd)).toBe(true)
  })

  it("F command sets flyoutFocused and highlights first flyout item", () => {
    const items = setupFlyout(true, 3)
    const h = makeHook()
    const cmd = COMMANDS.find(c => c.id === "flyout.focus")!
    h.executeCommand(cmd)
    expect(h.flyoutFocused).toBe(true)
    expect(h.listFocusIndex).toBe(0)
    expect(items[0].classList.contains("vim-nav-focused")).toBe(true)
  })

  it("F is a no-op when there are no flyout items", () => {
    setupFlyout(true, 0)
    const h = makeHook()
    const cmd = COMMANDS.find(c => c.id === "flyout.focus")!
    h.executeCommand(cmd)
    expect(h.flyoutFocused).toBe(false)
  })

  it("j navigates flyout items when flyoutFocused is true", () => {
    const items = setupFlyout(true, 3)
    const h = makeHook()
    h.executeCommand(COMMANDS.find(c => c.id === "flyout.focus")!)
    h.executeCommand(COMMANDS.find(c => c.id === "list.next")!)
    expect(h.listFocusIndex).toBe(1)
    expect(items[1].classList.contains("vim-nav-focused")).toBe(true)
    expect(items[0].classList.contains("vim-nav-focused")).toBe(false)
  })

  it("Enter clicks the focused flyout item", () => {
    const items = setupFlyout(true, 2)
    const clickSpy = vi.fn()
    items[0].addEventListener("click", clickSpy)
    const h = makeHook()
    h.executeCommand(COMMANDS.find(c => c.id === "flyout.focus")!)
    h.executeCommand(COMMANDS.find(c => c.id === "list.open")!)
    expect(clickSpy).toHaveBeenCalledTimes(1)
  })

  it("close_flyout push_event clears flyoutFocused", () => {
    setupFlyout(true)
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    h.executeCommand(COMMANDS.find(c => c.id === "flyout.focus")!)
    expect(h.flyoutFocused).toBe(true)
    h.executeCommand(COMMANDS.find(c => c.id === "global.close")!)
    expect(h.flyoutFocused).toBe(false)
    expect(h.listFocusIndex).toBe(-1)
    expect(h.pushEventToShell).toHaveBeenCalledWith("close_flyout", {})
  })

  it("currentListItems falls back to main list when flyout closes externally", () => {
    setupFlyout(true, 2)
    const h = makeHook()
    h.executeCommand(COMMANDS.find(c => c.id === "flyout.focus")!)
    expect(h.flyoutFocused).toBe(true)
    document.body.innerHTML = ""
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    const item = document.createElement("li")
    item.setAttribute("data-vim-list-item", "")
    list.appendChild(item)
    document.body.appendChild(list)
    const items = h.currentListItems()
    expect(h.flyoutFocused).toBe(false)
    expect(items).toHaveLength(1)
    expect(items[0]).toBe(item)
  })

  it("clearListFocus resets flyoutFocused", () => {
    setupFlyout(true)
    const h = makeHook()
    h.executeCommand(COMMANDS.find(c => c.id === "flyout.focus")!)
    h.clearListFocus()
    expect(h.flyoutFocused).toBe(false)
    expect(h.listFocusIndex).toBe(-1)
  })
})

describe("toggle+focus commands (t<Upper>)", () => {
  beforeEach(() => { document.body.innerHTML = "" })
  afterEach(() => { document.body.innerHTML = "" })

  function setupFlyoutClosed(): void {
    const panel = document.createElement("div")
    panel.setAttribute("data-vim-flyout-open", "false")
    document.body.appendChild(panel)
  }

  function openFlyoutWithItems(count = 3): HTMLElement[] {
    const panel = document.createElement("div")
    panel.setAttribute("data-vim-flyout-open", "true")
    const items: HTMLElement[] = []
    for (let i = 0; i < count; i++) {
      const a = document.createElement("a")
      a.setAttribute("data-vim-flyout-item", "")
      panel.appendChild(a)
      items.push(a)
    }
    document.body.appendChild(panel)
    return items
  }

  it("9 toggle+focus commands are registered (tS through tJ)", () => {
    const ids = ["toggle.sessions.focus","toggle.tasks.focus","toggle.notes.focus",
      "toggle.files.focus","toggle.canvas.focus","toggle.chat.focus",
      "toggle.skills.focus","toggle.teams.focus","toggle.jobs.focus"]
    for (const id of ids) {
      expect(COMMANDS.find(c => c.id === id), `missing ${id}`).toBeTruthy()
    }
  })

  it("each t<Upper> command has keys ['t', <Upper>] and focus_flyout_after true", () => {
    const pairs: [string, string][] = [
      ["toggle.sessions.focus","S"],["toggle.tasks.focus","T"],["toggle.notes.focus","N"],
      ["toggle.files.focus","F"],["toggle.canvas.focus","W"],["toggle.chat.focus","C"],
      ["toggle.skills.focus","K"],["toggle.teams.focus","M"],["toggle.jobs.focus","J"],
    ]
    for (const [id, letter] of pairs) {
      const cmd = COMMANDS.find(c => c.id === id)!
      expect(cmd.keys).toEqual(["t", letter])
      expect((cmd.action as any).focus_flyout_after).toBe(true)
    }
  })

  it("t<Upper> commands are distinct from their t<lower> counterparts", () => {
    expect(COMMANDS.find(c => c.keys[0] === "t" && c.keys[1] === "S")).toBeTruthy()
    expect(COMMANDS.find(c => c.keys[0] === "t" && c.keys[1] === "s")).toBeTruthy()
  })

  it("_focusFlyoutAfterOpen immediately focuses when flyout already open", () => {
    const items = openFlyoutWithItems(3)
    const h = makeHook()
    h._focusFlyoutAfterOpen()
    expect(h.flyoutFocused).toBe(true)
    expect(h.listFocusIndex).toBe(0)
    expect(items[0].classList.contains("vim-nav-focused")).toBe(true)
  })

  it("_focusFlyoutAfterOpen is a no-op when flyout opens with no items", () => {
    const panel = document.createElement("div")
    panel.setAttribute("data-vim-flyout-open", "true")
    document.body.appendChild(panel)
    const h = makeHook()
    h._focusFlyoutAfterOpen()
    expect(h.flyoutFocused).toBe(false)
  })

  it("_focusFlyoutAfterOpen uses MutationObserver when flyout is initially closed", async () => {
    setupFlyoutClosed()
    const h = makeHook()
    h._focusFlyoutAfterOpen()
    expect(h.flyoutFocused).toBe(false)

    // Simulate flyout opening: set attribute to true and add items
    const panel = document.querySelector("[data-vim-flyout-open]") as HTMLElement
    const item = document.createElement("a")
    item.setAttribute("data-vim-flyout-item", "")
    panel.appendChild(item)
    panel.setAttribute("data-vim-flyout-open", "true")

    // Allow MutationObserver microtask to fire
    await new Promise(r => setTimeout(r, 0))
    expect(h.flyoutFocused).toBe(true)
    expect(h.listFocusIndex).toBe(0)
  })
})

describe("toggle+focus: open-with-late-items path", () => {
  beforeEach(() => { document.body.innerHTML = "" })
  afterEach(() => { document.body.innerHTML = "" })

  it("focuses items inserted AFTER flyout was already open", async () => {
    // Flyout already marked open, but items haven't rendered yet
    const panel = document.createElement("div")
    panel.setAttribute("data-vim-flyout-open", "true")
    document.body.appendChild(panel)

    const h = makeHook()
    h._focusFlyoutAfterOpen()
    expect(h.flyoutFocused).toBe(false)

    // Items appear later via LiveView patch — childList mutation
    const item = document.createElement("a")
    item.setAttribute("data-vim-flyout-item", "")
    panel.appendChild(item)

    await new Promise(r => setTimeout(r, 0))
    expect(h.flyoutFocused).toBe(true)
    expect(h.listFocusIndex).toBe(0)
    expect(item.classList.contains("vim-nav-focused")).toBe(true)
  })
})

describe("rail coverage: g and t bindings for all rail items", () => {
  it("nav commands exist for all rail items", () => {
    const navIds = [
      "nav.sessions","nav.tasks","nav.notes","nav.canvas","nav.agents","nav.kanban",
      "nav.files","nav.prompts","nav.chat","nav.jobs","nav.usage","nav.teams",
      "nav.skills","nav.notifications",
    ]
    for (const id of navIds) {
      expect(COMMANDS.find(c => c.id === id), `missing ${id}`).toBeTruthy()
    }
  })

  it("toggle commands exist for all toggleable rail sections", () => {
    const toggleIds = [
      "toggle.sessions","toggle.tasks","toggle.notes","toggle.files","toggle.canvas",
      "toggle.chat","toggle.skills","toggle.teams","toggle.jobs","toggle.agents",
      "toggle.usage","toggle.notifications","toggle.prompts",
    ]
    for (const id of toggleIds) {
      expect(COMMANDS.find(c => c.id === id), `missing ${id}`).toBeTruthy()
    }
  })

  it("no key conflicts in g namespace", () => {
    const gKeys = COMMANDS.filter(c => c.keys[0] === "g" && c.keys.length === 2).map(c => c.keys[1])
    expect(new Set(gKeys).size).toBe(gKeys.length)
  })

  it("no key conflicts in t namespace", () => {
    const tKeys = COMMANDS.filter(c => c.keys[0] === "t" && c.keys.length === 2).map(c => c.keys[1])
    expect(new Set(tKeys).size).toBe(tKeys.length)
  })

  it("project-scoped nav commands use relative paths", () => {
    const relativeIds = ["nav.files","nav.prompts","nav.jobs","nav.teams","nav.skills"]
    for (const id of relativeIds) {
      const cmd = COMMANDS.find(c => c.id === id)!
      expect((cmd.action as any).relative).toBe(true)
    }
  })

  it("global nav commands use absolute paths", () => {
    const absoluteCases: [string, string][] = [
      ["nav.chat", "/chat"],
      ["nav.usage", "/usage"],
      ["nav.notifications", "/notifications"],
    ]
    for (const [id, path] of absoluteCases) {
      const cmd = COMMANDS.find(c => c.id === id)!
      expect((cmd.action as any).path).toBe(path)
      expect((cmd.action as any).relative).toBeFalsy()
    }
  })

  it("tp remains proj_picker (not repurposed); prompts uses tP (capital)", () => {
    const tp = COMMANDS.find(c => c.keys[0] === "t" && c.keys[1] === "p")!
    expect(tp.id).toBe("toggle.proj_picker")
    const tP = COMMANDS.find(c => c.keys[0] === "t" && c.keys[1] === "P")!
    expect(tP.id).toBe("toggle.prompts")
  })
})

describe("gg/G list jump commands", () => {
  beforeEach(() => { document.body.innerHTML = "" })

  function makeList(itemCount: number): HTMLElement {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    for (let i = 0; i < itemCount; i++) {
      const item = document.createElement("li")
      item.setAttribute("data-vim-list-item", "")
      item.textContent = `Item ${i}`
      list.appendChild(item)
    }
    document.body.appendChild(list)
    return list
  }

  it("list.top command exists with keys [g,g] and scope feature:vim-list", () => {
    const cmd = COMMANDS.find(c => c.id === "list.top")!
    expect(cmd).toBeDefined()
    expect(cmd.keys).toEqual(["g", "g"])
    expect(cmd.scope).toBe("feature:vim-list")
    expect(cmd.action.kind).toBe("client")
    if (cmd.action.kind === "client") expect(cmd.action.name).toBe("list_top")
  })

  it("list.bottom command exists with keys [G] and scope feature:vim-list", () => {
    const cmd = COMMANDS.find(c => c.id === "list.bottom")!
    expect(cmd).toBeDefined()
    expect(cmd.keys).toEqual(["G"])
    expect(cmd.scope).toBe("feature:vim-list")
    expect(cmd.action.kind).toBe("client")
    if (cmd.action.kind === "client") expect(cmd.action.name).toBe("list_bottom")
  })

  it("gg focuses the first item", () => {
    makeList(4)
    const h = makeHook()
    h.listFocusIndex = 3
    const cmd = COMMANDS.find(c => c.id === "list.top")!
    h.executeCommand(cmd)
    expect(h.listFocusIndex).toBe(0)
    const items = document.querySelectorAll("[data-vim-list-item]")
    expect(items[0].classList.contains("vim-nav-focused")).toBe(true)
    expect(items[3].classList.contains("vim-nav-focused")).toBe(false)
  })

  it("gg when already at bottom goes to first item", () => {
    makeList(5)
    const h = makeHook()
    h.listFocusIndex = 4
    const cmd = COMMANDS.find(c => c.id === "list.top")!
    h.executeCommand(cmd)
    expect(h.listFocusIndex).toBe(0)
  })

  it("G focuses the last item", () => {
    makeList(4)
    const h = makeHook()
    h.listFocusIndex = 0
    const cmd = COMMANDS.find(c => c.id === "list.bottom")!
    h.executeCommand(cmd)
    expect(h.listFocusIndex).toBe(3)
    const items = document.querySelectorAll("[data-vim-list-item]")
    expect(items[3].classList.contains("vim-nav-focused")).toBe(true)
    expect(items[0].classList.contains("vim-nav-focused")).toBe(false)
  })

  it("G when already at top goes to last item", () => {
    makeList(5)
    const h = makeHook()
    h.listFocusIndex = 0
    const cmd = COMMANDS.find(c => c.id === "list.bottom")!
    h.executeCommand(cmd)
    expect(h.listFocusIndex).toBe(4)
  })

  it("gg is a no-op when no data-vim-list exists", () => {
    const h = makeHook()
    h.listFocusIndex = -1
    const cmd = COMMANDS.find(c => c.id === "list.top")!
    h.executeCommand(cmd)
    expect(h.listFocusIndex).toBe(-1)
  })

  it("G is a no-op when no data-vim-list exists", () => {
    const h = makeHook()
    h.listFocusIndex = -1
    const cmd = COMMANDS.find(c => c.id === "list.bottom")!
    h.executeCommand(cmd)
    expect(h.listFocusIndex).toBe(-1)
  })

  it("G is not in PREFIXES (single key, not a prefix)", () => {
    expect(PREFIXES.has("G")).toBe(false)
  })

  it("g remains in PREFIXES for both nav and gg", () => {
    expect(PREFIXES.has("g")).toBe(true)
  })
})

describe("Space f t find-task palette command", () => {
  beforeEach(() => { document.body.innerHTML = "" })

  it("leader.find.tasks command exists with keys [Space,f,t]", () => {
    const cmd = COMMANDS.find(c => c.id === "leader.find.tasks")!
    expect(cmd).toBeDefined()
    expect(cmd.keys).toEqual(["Space", "f", "t"])
    expect(cmd.action.kind).toBe("client")
    if (cmd.action.kind === "client") expect(cmd.action.name).toBe("find_tasks")
  })

  it("find_tasks dispatches palette:open-command with commandId list-tasks", () => {
    const palette = document.createElement("div")
    palette.id = "command-palette"
    document.body.appendChild(palette)
    const listener = vi.fn()
    palette.addEventListener("palette:open-command", listener)
    const h = makeHook()
    const cmd = COMMANDS.find(c => c.id === "leader.find.tasks")!
    h.executeCommand(cmd)
    expect(listener).toHaveBeenCalledTimes(1)
    const detail = (listener.mock.calls[0][0] as CustomEvent).detail
    expect(detail.commandId).toBe("list-tasks")
  })

  it("leader.find.notes command exists with keys [Space,f,n]", () => {
    const cmd = COMMANDS.find(c => c.id === "leader.find.notes")!
    expect(cmd).toBeDefined()
    expect(cmd.keys).toEqual(["Space", "f", "n"])
    expect(cmd.action.kind).toBe("client")
    if (cmd.action.kind === "client") expect(cmd.action.name).toBe("find_notes")
  })

  it("find_notes dispatches palette:open-command with commandId list-notes", () => {
    const palette = document.createElement("div")
    palette.id = "command-palette"
    document.body.appendChild(palette)
    const listener = vi.fn()
    palette.addEventListener("palette:open-command", listener)
    const h = makeHook()
    const cmd = COMMANDS.find(c => c.id === "leader.find.notes")!
    h.executeCommand(cmd)
    expect(listener).toHaveBeenCalledTimes(1)
    const detail = (listener.mock.calls[0][0] as CustomEvent).detail
    expect(detail.commandId).toBe("list-notes")
  })

  it("leader.project.picker command exists with keys [Space,p,p]", () => {
    const cmd = COMMANDS.find(c => c.id === "leader.project.picker")!
    expect(cmd).toBeDefined()
    expect(cmd.keys).toEqual(["Space", "p", "p"])
    expect(cmd.action.kind).toBe("client")
    if (cmd.action.kind === "client") expect(cmd.action.name).toBe("find_projects")
  })

  it("find_projects dispatches palette:open-command with commandId list-projects", () => {
    const palette = document.createElement("div")
    palette.id = "command-palette"
    document.body.appendChild(palette)
    const listener = vi.fn()
    palette.addEventListener("palette:open-command", listener)
    const h = makeHook()
    const cmd = COMMANDS.find(c => c.id === "leader.project.picker")!
    h.executeCommand(cmd)
    expect(listener).toHaveBeenCalledTimes(1)
    const detail = (listener.mock.calls[0][0] as CustomEvent).detail
    expect(detail.commandId).toBe("list-projects")
  })
})

describe("VimNav numeric count prefix", () => {
  beforeEach(() => {
    vi.useFakeTimers()
    document.body.innerHTML = ""
  })
  afterEach(() => {
    vi.useRealTimers()
    document.body.innerHTML = ""
  })

  function makeList(itemCount: number): HTMLElement {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    for (let i = 0; i < itemCount; i++) {
      const item = document.createElement("li")
      item.setAttribute("data-vim-list-item", "")
      item.textContent = `Item ${i}`
      list.appendChild(item)
    }
    document.body.appendChild(list)
    return list
  }

  function pressKey(h: any, key: string): void {
    const evt = new KeyboardEvent("keydown", { key })
    Object.defineProperty(evt, "target", { value: document.body, configurable: true })
    h.handleKey(evt)
  }

  it("j without prefix still moves 1", () => {
    makeList(5)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0
    pressKey(h, "j")
    expect(h.listFocusIndex).toBe(1)
  })

  it("3j moves focus 3 items down from current position", () => {
    makeList(10)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0
    pressKey(h, "3")
    expect(h.count).toBe(3)
    pressKey(h, "j")
    expect(h.listFocusIndex).toBe(3)
  })

  it("5k moves focus 5 items up", () => {
    makeList(10)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 7
    pressKey(h, "5")
    pressKey(h, "k")
    expect(h.listFocusIndex).toBe(2)
  })

  it("count is reset to 0 after executing a command", () => {
    makeList(5)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0
    pressKey(h, "3")
    expect(h.count).toBe(3)
    pressKey(h, "j")
    expect(h.count).toBe(0)
  })

  it("count accumulates across multiple digit presses (typing 1 then 2 gives count 12)", () => {
    const h = makeHook()
    h.mode = "normal"
    pressKey(h, "1")
    pressKey(h, "2")
    expect(h.count).toBe(12)
  })

  it("12j moves 12 items, clamped to list length", () => {
    makeList(5)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0
    pressKey(h, "1")
    pressKey(h, "2")
    pressKey(h, "j")
    expect(h.listFocusIndex).toBe(4)
  })

  it("5G jumps to the 5th item (index 4)", () => {
    makeList(10)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0
    pressKey(h, "5")
    pressKey(h, "G")
    expect(h.listFocusIndex).toBe(4)
  })

  it("count resets when Escape is pressed", () => {
    const h = makeHook()
    h.mode = "normal"
    pressKey(h, "3")
    expect(h.count).toBe(3)
    pressKey(h, "Escape")
    expect(h.count).toBe(0)
  })

  it("count resets after 2s inactivity", () => {
    const h = makeHook()
    h.mode = "normal"
    pressKey(h, "5")
    expect(h.count).toBe(5)
    vi.advanceTimersByTime(2000)
    expect(h.count).toBe(0)
  })

  it("statusbar shows count when count > 0", () => {
    const h = makeHook()
    h.mounted()
    pressKey(h, "3")
    expect(h.statusbarEl?.textContent).toContain("3")
    h.destroyed()
  })
})

describe("{/} group jump commands", () => {
  beforeEach(() => { document.body.innerHTML = "" })

  function makeList(count: number): HTMLElement[] {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    const items: HTMLElement[] = []
    for (let i = 0; i < count; i++) {
      const item = document.createElement("li")
      item.setAttribute("data-vim-list-item", "")
      item.textContent = `Item ${i}`
      list.appendChild(item)
      items.push(item)
    }
    document.body.appendChild(list)
    return items
  }

  function makeListWithGroups(): { items: HTMLElement[]; seps: HTMLElement[] } {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    const items: HTMLElement[] = []
    const seps: HTMLElement[] = []

    const sep1 = document.createElement("li")
    sep1.setAttribute("data-vim-list-group", "")
    sep1.textContent = "Group A"
    list.appendChild(sep1)
    seps.push(sep1)

    for (let i = 0; i < 3; i++) {
      const item = document.createElement("li")
      item.setAttribute("data-vim-list-item", "")
      list.appendChild(item)
      items.push(item)
    }

    const sep2 = document.createElement("li")
    sep2.setAttribute("data-vim-list-group", "")
    sep2.textContent = "Group B"
    list.appendChild(sep2)
    seps.push(sep2)

    for (let i = 3; i < 6; i++) {
      const item = document.createElement("li")
      item.setAttribute("data-vim-list-item", "")
      list.appendChild(item)
      items.push(item)
    }

    document.body.appendChild(list)
    return { items, seps }
  }

  it("list.group_prev and list.group_next commands registered with feature:vim-list scope", () => {
    const prev = COMMANDS.find(c => c.id === "list.group_prev")!
    const next = COMMANDS.find(c => c.id === "list.group_next")!
    expect(prev).toBeDefined()
    expect(next).toBeDefined()
    expect(prev.keys).toEqual(["{"])
    expect(next.keys).toEqual(["}"])
    expect(prev.scope).toBe("feature:vim-list")
    expect(next.scope).toBe("feature:vim-list")
  })

  it("} with no separators falls back to list_bottom (last item)", () => {
    const items = makeList(5)
    const h = makeHook()
    h.listFocusIndex = 1
    h.executeCommand(COMMANDS.find(c => c.id === "list.group_next")!)
    expect(h.listFocusIndex).toBe(4)
    expect(items[4].classList.contains("vim-nav-focused")).toBe(true)
  })

  it("{ with no separators falls back to list_top (first item)", () => {
    const items = makeList(5)
    const h = makeHook()
    h.listFocusIndex = 3
    h.executeCommand(COMMANDS.find(c => c.id === "list.group_prev")!)
    expect(h.listFocusIndex).toBe(0)
    expect(items[0].classList.contains("vim-nav-focused")).toBe(true)
  })

  it("{/} are no-ops when no list exists", () => {
    const h = makeHook()
    h.listFocusIndex = -1
    expect(() => h.executeCommand(COMMANDS.find(c => c.id === "list.group_next")!)).not.toThrow()
    expect(() => h.executeCommand(COMMANDS.find(c => c.id === "list.group_prev")!)).not.toThrow()
    expect(h.listFocusIndex).toBe(-1)
  })

  it("} jumps to first item of next group (past separator)", () => {
    const { items } = makeListWithGroups()
    const h = makeHook()
    h.listFocusIndex = 0
    h.focusListItem(0)
    h.executeCommand(COMMANDS.find(c => c.id === "list.group_next")!)
    // items[3] is the first item of group B
    expect(h.listFocusIndex).toBe(3)
    expect(items[3].classList.contains("vim-nav-focused")).toBe(true)
  })

  it("{ from middle of group B jumps to first item of group B", () => {
    const { items } = makeListWithGroups()
    const h = makeHook()
    h.listFocusIndex = 4
    h.focusListItem(4)
    h.executeCommand(COMMANDS.find(c => c.id === "list.group_prev")!)
    // First item of group B is items[3]
    expect(h.listFocusIndex).toBe(3)
    expect(items[3].classList.contains("vim-nav-focused")).toBe(true)
  })

  it("{ from first item of group B jumps to first item of group A", () => {
    const { items } = makeListWithGroups()
    const h = makeHook()
    h.listFocusIndex = 3
    h.focusListItem(3)
    h.executeCommand(COMMANDS.find(c => c.id === "list.group_prev")!)
    // First item of group A is items[0]
    expect(h.listFocusIndex).toBe(0)
    expect(items[0].classList.contains("vim-nav-focused")).toBe(true)
  })

  it("} from last group stays at last item when no next separator", () => {
    const { items } = makeListWithGroups()
    const h = makeHook()
    h.listFocusIndex = 4
    h.focusListItem(4)
    h.executeCommand(COMMANDS.find(c => c.id === "list.group_next")!)
    // No next separator after group B — clamps to last item
    expect(h.listFocusIndex).toBe(5)
    expect(items[5].classList.contains("vim-nav-focused")).toBe(true)
  })

  it("{ and } are not in PREFIXES (single keys)", () => {
    expect(PREFIXES.has("{")).toBe(false)
    expect(PREFIXES.has("}")).toBe(false)
  })
})

describe("generic dd/aa list item delete and archive", () => {
  beforeEach(() => { document.body.innerHTML = "" })

  function makeTypedList(types: Array<{ type: string; id: string }>): HTMLElement[] {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    const items: HTMLElement[] = []
    for (const { type, id } of types) {
      const item = document.createElement("li")
      item.setAttribute("data-vim-list-item", "")
      item.setAttribute("data-vim-item-type", type)
      item.setAttribute("data-vim-item-id", id)
      list.appendChild(item)
      items.push(item)
    }
    document.body.appendChild(list)
    return items
  }

  function makeUntaggedSessionList(count: number): HTMLElement[] {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    const items: HTMLElement[] = []
    for (let i = 0; i < count; i++) {
      const item = document.createElement("li")
      item.setAttribute("data-vim-list-item", "")
      item.setAttribute("data-session-id", String(i + 1))
      list.appendChild(item)
      items.push(item)
    }
    document.body.appendChild(list)
    return items
  }

  it("list.delete and list.archive commands registered with feature:vim-list scope", () => {
    const del = COMMANDS.find(c => c.id === "list.delete")!
    const arc = COMMANDS.find(c => c.id === "list.archive")!
    expect(del).toBeDefined()
    expect(arc).toBeDefined()
    expect(del.keys).toEqual(["d", "d"])
    expect(arc.keys).toEqual(["a", "a"])
    expect(del.scope).toBe("feature:vim-list")
    expect(arc.scope).toBe("feature:vim-list")
  })

  it("d is in PREFIXES when data-vim-list exists", () => {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    document.body.appendChild(list)
    expect(matchesKnownBindingOrPrefix([], "d")).toBe(true)
  })

  it("list_item_delete pushes delete_task for a task item", () => {
    makeTypedList([{ type: "task", id: "42" }])
    const h = makeHook()
    h.pushToList = vi.fn()
    h.listFocusIndex = 0
    h.focusListItem(0)
    h.executeCommand(COMMANDS.find(c => c.id === "list.delete")!)
    expect(h.pushToList).toHaveBeenCalledWith("delete_task", { item_type: "task", item_id: "42" })
  })

  it("list_item_archive pushes archive_task for a task item", () => {
    makeTypedList([{ type: "task", id: "7" }])
    const h = makeHook()
    h.pushToList = vi.fn()
    h.listFocusIndex = 0
    h.focusListItem(0)
    h.executeCommand(COMMANDS.find(c => c.id === "list.archive")!)
    expect(h.pushToList).toHaveBeenCalledWith("archive_task", { item_type: "task", item_id: "7" })
  })

  it("list_item_delete pushes delete_note for a note item", () => {
    makeTypedList([{ type: "note", id: "99" }])
    const h = makeHook()
    h.pushToList = vi.fn()
    h.listFocusIndex = 0
    h.focusListItem(0)
    h.executeCommand(COMMANDS.find(c => c.id === "list.delete")!)
    expect(h.pushToList).toHaveBeenCalledWith("delete_note", { item_type: "note", item_id: "99" })
  })

  it("list_item_archive pushes archive_session and includes session_id for session item", () => {
    makeTypedList([{ type: "session", id: "55" }])
    const h = makeHook()
    h.pushToList = vi.fn()
    h.listFocusIndex = 0
    h.focusListItem(0)
    h.executeCommand(COMMANDS.find(c => c.id === "list.archive")!)
    expect(h.pushToList).toHaveBeenCalledWith("archive_session", {
      item_type: "session", item_id: "55", session_id: "55"
    })
  })

  it("list_item_delete falls back to delete_session with session_id for untagged item", () => {
    makeUntaggedSessionList(2)
    const h = makeHook()
    h.pushToList = vi.fn()
    h.listFocusIndex = 0
    h.focusListItem(0)
    h.executeCommand(COMMANDS.find(c => c.id === "list.delete")!)
    expect(h.pushToList).toHaveBeenCalledWith("delete_session", { session_id: "1" })
  })

  it("list_item_archive is a no-op when no item is focused", () => {
    makeTypedList([{ type: "task", id: "1" }])
    const h = makeHook()
    h.pushToList = vi.fn()
    h.listFocusIndex = -1
    h.executeCommand(COMMANDS.find(c => c.id === "list.archive")!)
    expect(h.pushToList).not.toHaveBeenCalled()
  })

  it("list_item_delete refocuses after item removal", async () => {
    const items = makeTypedList([
      { type: "task", id: "1" },
      { type: "task", id: "2" },
      { type: "task", id: "3" },
    ])
    const h = makeHook()
    h.pushToList = vi.fn()
    h.listFocusIndex = 1
    h.focusListItem(1)
    h.executeCommand(COMMANDS.find(c => c.id === "list.delete")!)
    items[1].remove()
    await new Promise(r => setTimeout(r, 0))
    expect(h.listFocusIndex).toBe(1)
    const remaining = document.querySelectorAll("[data-vim-list-item]")
    expect(remaining[1].classList.contains("vim-nav-focused")).toBe(true)
  })
})

describe("ctrl-d/ctrl-u half-page scroll", () => {
  beforeEach(() => { document.body.innerHTML = "" })
  afterEach(() => { document.body.innerHTML = "" })

  function makeList(count: number, itemHeight = 48): HTMLElement[] {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    // jsdom doesn't lay out, so we mock clientHeight via Object.defineProperty
    Object.defineProperty(list, "clientHeight", { value: itemHeight * 10, configurable: true })
    const items: HTMLElement[] = []
    for (let i = 0; i < count; i++) {
      const item = document.createElement("li")
      item.setAttribute("data-vim-list-item", "")
      // offsetHeight is 0 in jsdom — set it so half-page calculation is deterministic
      Object.defineProperty(item, "offsetHeight", { value: itemHeight, configurable: true })
      list.appendChild(item)
      items.push(item)
    }
    document.body.appendChild(list)
    return items
  }

  function pressCtrl(h: any, key: "d" | "u"): void {
    const evt = new KeyboardEvent("keydown", { key, ctrlKey: true })
    Object.defineProperty(evt, "target", { value: document.body, configurable: true })
    h.handleKey(evt)
  }

  it("ctrl-d moves focus down by half the visible page count", () => {
    // clientHeight = 480, itemHeight = 48 → 10 visible → halfPage = 5
    makeList(20)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0
    pressCtrl(h, "d")
    expect(h.listFocusIndex).toBe(5)
  })

  it("ctrl-u moves focus up by half the visible page count", () => {
    makeList(20)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 10
    pressCtrl(h, "u")
    expect(h.listFocusIndex).toBe(5)
  })

  it("ctrl-d clamps at the last item", () => {
    makeList(8)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 6
    pressCtrl(h, "d")
    expect(h.listFocusIndex).toBe(7)
  })

  it("ctrl-u clamps at 0", () => {
    makeList(8)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 2
    pressCtrl(h, "u")
    expect(h.listFocusIndex).toBe(0)
  })

  it("ctrl-d with no list does nothing", () => {
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0
    // No list in DOM
    pressCtrl(h, "d")
    expect(h.listFocusIndex).toBe(0)
  })

  it("ctrl-d when listFocusIndex is -1 starts from item 0", () => {
    makeList(20)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = -1
    pressCtrl(h, "d")
    expect(h.listFocusIndex).toBe(5)
  })

  it("ctrl-u when listFocusIndex is -1 starts from item 0 and clamps to 0", () => {
    makeList(20)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = -1
    pressCtrl(h, "u")
    expect(h.listFocusIndex).toBe(0)
  })

  it("ctrl-d in insert mode does nothing", () => {
    makeList(20)
    const h = makeHook()
    h.mode = "insert"
    h.listFocusIndex = 0
    pressCtrl(h, "d")
    // insert mode returns early before the ctrl check
    expect(h.listFocusIndex).toBe(0)
  })

  it("ctrl-d on an editable target does nothing", () => {
    makeList(10)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0
    const input = document.createElement("input")
    document.body.appendChild(input)
    const evt = new KeyboardEvent("keydown", { key: "d", ctrlKey: true })
    Object.defineProperty(evt, "target", { value: input, configurable: true })
    h.handleKey(evt)
    expect(h.listFocusIndex).toBe(0)
  })
})

describe("o open in new tab", () => {
  beforeEach(() => { document.body.innerHTML = "" })
  afterEach(() => { document.body.innerHTML = "" })

  function makeListWithLinks(): { items: HTMLElement[]; links: HTMLAnchorElement[] } {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    const items: HTMLElement[] = []
    const links: HTMLAnchorElement[] = []
    for (let i = 0; i < 3; i++) {
      const item = document.createElement("li")
      item.setAttribute("data-vim-list-item", "")
      const a = document.createElement("a")
      a.href = `/sessions/${i}`
      a.textContent = `Session ${i}`
      item.appendChild(a)
      list.appendChild(item)
      items.push(item)
      links.push(a)
    }
    document.body.appendChild(list)
    return { items, links }
  }

  it("list.open_tab command is registered with feature:vim-list scope and key o", () => {
    const cmd = COMMANDS.find(c => c.id === "list.open_tab")!
    expect(cmd).toBeDefined()
    expect(cmd.keys).toEqual(["o"])
    expect(cmd.scope).toBe("feature:vim-list")
    expect(cmd.action).toEqual({ kind: "client", name: "list_open_tab" })
  })

  it("o opens href of child anchor in new tab", () => {
    const { items } = makeListWithLinks()
    const windowOpenSpy = vi.spyOn(window, "open").mockImplementation(() => null)
    const h = makeHook()
    h.listFocusIndex = 1
    h.focusListItem(1)
    h.executeCommand(COMMANDS.find(c => c.id === "list.open_tab")!)
    expect(windowOpenSpy).toHaveBeenCalledWith("/sessions/1", "_blank", "noopener,noreferrer")
    windowOpenSpy.mockRestore()
  })

  it("o uses href from item that is itself an anchor", () => {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    const a = document.createElement("a")
    a.setAttribute("data-vim-list-item", "")
    a.href = "/projects/5/sessions"
    list.appendChild(a)
    document.body.appendChild(list)

    const windowOpenSpy = vi.spyOn(window, "open").mockImplementation(() => null)
    const h = makeHook()
    h.listFocusIndex = 0
    h.focusListItem(0)
    h.executeCommand(COMMANDS.find(c => c.id === "list.open_tab")!)
    expect(windowOpenSpy).toHaveBeenCalledWith("/projects/5/sessions", "_blank", "noopener,noreferrer")
    windowOpenSpy.mockRestore()
  })

  it("o does nothing when listFocusIndex is -1", () => {
    makeListWithLinks()
    const windowOpenSpy = vi.spyOn(window, "open").mockImplementation(() => null)
    const h = makeHook()
    h.listFocusIndex = -1
    h.executeCommand(COMMANDS.find(c => c.id === "list.open_tab")!)
    expect(windowOpenSpy).not.toHaveBeenCalled()
    windowOpenSpy.mockRestore()
  })

  it("o does nothing when focused item has no anchor", () => {
    const list = document.createElement("ul")
    list.setAttribute("data-vim-list", "")
    const item = document.createElement("li")
    item.setAttribute("data-vim-list-item", "")
    item.textContent = "plain text"
    list.appendChild(item)
    document.body.appendChild(list)

    const windowOpenSpy = vi.spyOn(window, "open").mockImplementation(() => null)
    const h = makeHook()
    h.listFocusIndex = 0
    h.focusListItem(0)
    h.executeCommand(COMMANDS.find(c => c.id === "list.open_tab")!)
    expect(windowOpenSpy).not.toHaveBeenCalled()
    windowOpenSpy.mockRestore()
  })
})

// ---------------------------------------------------------------------------
// Hint mode (f key)
// ---------------------------------------------------------------------------

function makeListWithItems(count: number): HTMLElement[] {
  const list = document.createElement("ul")
  list.setAttribute("data-vim-list", "")
  const items: HTMLElement[] = []
  for (let i = 0; i < count; i++) {
    const li = document.createElement("li")
    li.setAttribute("data-vim-list-item", "")
    li.textContent = `Item ${i}`
    list.appendChild(li)
    items.push(li)
  }
  document.body.appendChild(list)
  return items
}

describe("hint mode (f key)", () => {
  beforeEach(() => { document.body.innerHTML = "" })
  afterEach(() => { document.body.innerHTML = "" })

  it("f command is registered with scope feature:vim-list", () => {
    const cmd = COMMANDS.find(c => c.id === "list.hint")!
    expect(cmd).toBeDefined()
    expect(cmd.keys).toEqual(["f"])
    expect(cmd.scope).toBe("feature:vim-list")
    expect(cmd.action.kind).toBe("client")
    if (cmd.action.kind === "client") expect(cmd.action.name).toBe("hint_mode_enter")
  })

  it("enterHintMode sets hintMode true and creates overlay", () => {
    makeListWithItems(3)
    const h = makeHook()
    h.mounted()
    h.enterHintMode()
    expect(h.hintMode).toBe(true)
    expect(h.hintOverlayEl).not.toBeNull()
    expect(document.getElementById("vim-nav-hints")).not.toBeNull()
  })

  it("enterHintMode creates one badge per list item", () => {
    makeListWithItems(5)
    const h = makeHook()
    h.mounted()
    h.enterHintMode()
    const badges = h.hintOverlayEl!.querySelectorAll("[data-hint-label]")
    expect(badges.length).toBe(5)
  })

  it("badges have sequential alphabetical labels", () => {
    makeListWithItems(3)
    const h = makeHook()
    h.mounted()
    h.enterHintMode()
    const labels = [...h.hintOverlayEl!.querySelectorAll<HTMLElement>("[data-hint-label]")]
      .map(b => b.dataset.hintLabel)
    expect(labels).toEqual(["a", "b", "c"])
  })

  it("exitHintMode removes overlay and resets state", () => {
    makeListWithItems(3)
    const h = makeHook()
    h.mounted()
    h.enterHintMode()
    h.exitHintMode()
    expect(h.hintMode).toBe(false)
    expect(h.hintOverlayEl).toBeNull()
    expect(document.getElementById("vim-nav-hints")).toBeNull()
  })

  it("Escape key exits hint mode", () => {
    makeListWithItems(3)
    const h = makeHook()
    h.mounted()
    h.enterHintMode()
    h.handleKey(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))
    expect(h.hintMode).toBe(false)
  })

  it("single matching letter auto-focuses item and exits", () => {
    makeListWithItems(3)
    const h = makeHook()
    h.mounted()
    h.enterHintMode()
    // 'a' is the label for item 0
    h.handleKey(new KeyboardEvent("keydown", { key: "a", bubbles: true }))
    expect(h.hintMode).toBe(false)
    expect(h.listFocusIndex).toBe(0)
  })

  it("two-char label: first char narrows to multiple matches, second resolves", () => {
    // Create 27 items so labels go a..z then aa
    makeListWithItems(27)
    const h = makeHook()
    h.mounted()
    h.enterHintMode()
    // After 26 single-char labels, 27th is "aa"
    expect(h.hintLabels[26].label).toBe("aa")
    // Pressing 'a' matches both "a" (item 0) and "aa" (item 26) — stays in hint mode
    h.handleKey(new KeyboardEvent("keydown", { key: "a", bubbles: true }))
    expect(h.hintMode).toBe(true)
    expect(h.hintBuffer).toBe("a")
    // Second 'a' makes buffer "aa" — exact match for item 26
    h.handleKey(new KeyboardEvent("keydown", { key: "a", bubbles: true }))
    expect(h.hintMode).toBe(false)
    expect(h.listFocusIndex).toBe(26)
  })

  it("no matching label exits hint mode", () => {
    makeListWithItems(3) // labels: a, b, c
    const h = makeHook()
    h.mounted()
    h.enterHintMode()
    h.handleKey(new KeyboardEvent("keydown", { key: "z", bubbles: true }))
    expect(h.hintMode).toBe(false)
  })

  it("enterHintMode does nothing when no list items", () => {
    const h = makeHook()
    h.mounted()
    h.enterHintMode()
    expect(h.hintMode).toBe(false)
    expect(h.hintOverlayEl).toBeNull()
  })

  it("clearListFocus exits hint mode if active", () => {
    makeListWithItems(3)
    const h = makeHook()
    h.mounted()
    h.enterHintMode()
    expect(h.hintMode).toBe(true)
    h.clearListFocus()
    expect(h.hintMode).toBe(false)
  })
})

describe("ctrl-n/ctrl-p single-step list navigation", () => {
  beforeEach(() => { document.body.innerHTML = "" })
  afterEach(() => { document.body.innerHTML = "" })

  function makeList(count: number): HTMLElement[] {
    const ul = document.createElement("ul")
    ul.setAttribute("data-vim-list", "")
    const items: HTMLElement[] = []
    for (let i = 0; i < count; i++) {
      const li = document.createElement("li")
      li.setAttribute("data-vim-list-item", "")
      Object.defineProperty(li, "offsetHeight", { value: 48, configurable: true })
      ul.appendChild(li)
      items.push(li)
    }
    document.body.appendChild(ul)
    return items
  }

  function press(h: any, key: "n" | "p"): void {
    const evt = new KeyboardEvent("keydown", { key, ctrlKey: true })
    Object.defineProperty(evt, "target", { value: document.body, configurable: true })
    h.handleKey(evt)
  }

  it("ctrl-n moves focus to the next item", () => {
    makeList(5)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 1
    press(h, "n")
    expect(h.listFocusIndex).toBe(2)
  })

  it("ctrl-p moves focus to the previous item", () => {
    makeList(5)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 3
    press(h, "p")
    expect(h.listFocusIndex).toBe(2)
  })

  it("ctrl-n clamps at last item", () => {
    makeList(3)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 2
    press(h, "n")
    expect(h.listFocusIndex).toBe(2)
  })

  it("ctrl-p clamps at 0", () => {
    makeList(3)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0
    press(h, "p")
    expect(h.listFocusIndex).toBe(0)
  })

  it("ctrl-n with listFocusIndex -1 starts from item 0", () => {
    makeList(5)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = -1
    press(h, "n")
    expect(h.listFocusIndex).toBe(1)
  })

  it("ctrl-n does nothing when no list exists", () => {
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0
    press(h, "n")
    expect(h.listFocusIndex).toBe(0)
  })
})

describe("y t yank focused item title", () => {
  beforeEach(() => { document.body.innerHTML = "" })
  afterEach(() => { document.body.innerHTML = "" })

  function makeListWithTitles(titles: string[]): HTMLElement[] {
    const ul = document.createElement("ul")
    ul.setAttribute("data-vim-list", "")
    const items: HTMLElement[] = []
    for (const title of titles) {
      const li = document.createElement("li")
      li.setAttribute("data-vim-list-item", "")
      li.setAttribute("data-vim-item-title", title)
      ul.appendChild(li)
      items.push(li)
    }
    document.body.appendChild(ul)
    return items
  }

  const yankTitleCmd = { id: "list.yank_title", label: "Copy title", keys: ["y", "t"], group: "context" as const, action: { kind: "client" as const, name: "list_yank_title" as const }, scope: "feature:vim-list" }

  it("copies data-vim-item-title of focused item to clipboard", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    Object.defineProperty(navigator, "clipboard", { value: { writeText }, configurable: true })

    makeListWithTitles(["Alpha", "Beta", "Gamma"])
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 1

    h.executeCommand(yankTitleCmd)

    expect(writeText).toHaveBeenCalledWith("Beta")
  })

  it("does nothing when no item is focused (listFocusIndex -1)", () => {
    const writeText = vi.fn()
    Object.defineProperty(navigator, "clipboard", { value: { writeText }, configurable: true })

    makeListWithTitles(["Alpha"])
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = -1

    h.executeCommand(yankTitleCmd)

    expect(writeText).not.toHaveBeenCalled()
  })

  it("does nothing when focused item has no data-vim-item-title", () => {
    const writeText = vi.fn()
    Object.defineProperty(navigator, "clipboard", { value: { writeText }, configurable: true })

    const ul = document.createElement("ul")
    ul.setAttribute("data-vim-list", "")
    const li = document.createElement("li")
    li.setAttribute("data-vim-list-item", "")
    // no data-vim-item-title set
    ul.appendChild(li)
    document.body.appendChild(ul)

    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0

    h.executeCommand(yankTitleCmd)

    expect(writeText).not.toHaveBeenCalled()
  })
})

describe("r rename inline", () => {
  beforeEach(() => { document.body.innerHTML = "" })
  afterEach(() => { document.body.innerHTML = "" })

  const renameCmd = { id: "list.rename", label: "Rename item", keys: ["r"], group: "context" as const, action: { kind: "client" as const, name: "list_rename" as const }, scope: "feature:vim-list" }

  function makeListItemWithInput(selector: string): { item: HTMLElement; input: HTMLInputElement } {
    const ul = document.createElement("ul")
    ul.setAttribute("data-vim-list", "")
    const li = document.createElement("li")
    li.setAttribute("data-vim-list-item", "")
    li.dataset.vimRenameTarget = selector
    const input = document.createElement("input")
    input.type = "text"
    input.name = "name"
    li.appendChild(input)
    ul.appendChild(li)
    document.body.appendChild(ul)
    return { item: li, input }
  }

  it("focuses input and switches to insert mode when data-vim-rename-target exists", () => {
    const { input } = makeListItemWithInput('input[name="name"]')
    const focusSpy = vi.spyOn(input, "focus")
    const selectSpy = vi.spyOn(input, "select")

    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0

    h.executeCommand(renameCmd)

    expect(focusSpy).toHaveBeenCalled()
    expect(selectSpy).toHaveBeenCalled()
    expect(h.mode).toBe("insert")
  })

  it("no-op when listFocusIndex is -1", () => {
    const { input } = makeListItemWithInput('input[name="name"]')
    const focusSpy = vi.spyOn(input, "focus")

    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = -1

    h.executeCommand(renameCmd)

    expect(focusSpy).not.toHaveBeenCalled()
    expect(h.mode).toBe("normal")
  })

  it("no-op when focused item has no data-vim-rename-target", () => {
    const ul = document.createElement("ul")
    ul.setAttribute("data-vim-list", "")
    const li = document.createElement("li")
    li.setAttribute("data-vim-list-item", "")
    // no data-vim-rename-target
    const input = document.createElement("input")
    input.name = "name"
    li.appendChild(input)
    ul.appendChild(li)
    document.body.appendChild(ul)

    const focusSpy = vi.spyOn(input, "focus")
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0

    h.executeCommand(renameCmd)

    expect(focusSpy).not.toHaveBeenCalled()
    expect(h.mode).toBe("normal")
  })

  it("no-op when querySelector finds nothing", () => {
    const ul = document.createElement("ul")
    ul.setAttribute("data-vim-list", "")
    const li = document.createElement("li")
    li.setAttribute("data-vim-list-item", "")
    li.dataset.vimRenameTarget = 'input[name="title"]'
    // no input with name="title" inside li
    ul.appendChild(li)
    document.body.appendChild(ul)

    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0

    h.executeCommand(renameCmd)

    expect(h.mode).toBe("normal")
  })
})

describe("task nav commands (Space t n / Space t p)", () => {
  beforeEach(() => {
    document.body.innerHTML = ""
    Object.defineProperty(window, "location", {
      value: { pathname: "/projects/5/tasks", search: "", assign: vi.fn() },
      writable: true,
      configurable: true,
    })
  })
  afterEach(() => { document.body.innerHTML = "" })

  it("leader.task.next command has correct definition", () => {
    const cmd = COMMANDS.find(c => c.id === "leader.task.next")!
    expect(cmd).toBeDefined()
    expect(cmd.label).toBe("Next task")
    expect(cmd.keys).toEqual(["Space", "t", "n"])
    expect(cmd.group).toBe("navigation")
    expect(cmd.scope).toBe("route_suffix:/tasks")
    expect(cmd.action.kind).toBe("client")
    if (cmd.action.kind === "client") expect(cmd.action.name).toBe("task_nav_next")
  })

  it("leader.task.prev command has correct definition", () => {
    const cmd = COMMANDS.find(c => c.id === "leader.task.prev")!
    expect(cmd).toBeDefined()
    expect(cmd.label).toBe("Prev task")
    expect(cmd.keys).toEqual(["Space", "t", "p"])
    expect(cmd.group).toBe("navigation")
    expect(cmd.scope).toBe("route_suffix:/tasks")
    expect(cmd.action.kind).toBe("client")
    if (cmd.action.kind === "client") expect(cmd.action.name).toBe("task_nav_prev")
  })

  it("task_nav_next pushes vim:task-nav with direction next", () => {
    const h = makeHook()
    const cmd = COMMANDS.find(c => c.id === "leader.task.next")!
    h.executeCommand(cmd)
    expect(h.pushEvent).toHaveBeenCalledWith("vim:task-nav", expect.objectContaining({ direction: "next" }))
  })

  it("task_nav_prev pushes vim:task-nav with direction prev", () => {
    const h = makeHook()
    const cmd = COMMANDS.find(c => c.id === "leader.task.prev")!
    h.executeCommand(cmd)
    expect(h.pushEvent).toHaveBeenCalledWith("vim:task-nav", expect.objectContaining({ direction: "prev" }))
  })

  it("task_nav_next sends current_path from location.pathname", () => {
    const h = makeHook()
    const cmd = COMMANDS.find(c => c.id === "leader.task.next")!
    h.executeCommand(cmd)
    expect(h.pushEvent).toHaveBeenCalledWith("vim:task-nav", expect.objectContaining({
      current_path: "/projects/5/tasks"
    }))
  })

  it("task_nav_next sends task_uuid null when no ?task= in search", () => {
    const h = makeHook()
    const cmd = COMMANDS.find(c => c.id === "leader.task.next")!
    h.executeCommand(cmd)
    expect(h.pushEvent).toHaveBeenCalledWith("vim:task-nav", expect.objectContaining({
      task_uuid: null
    }))
  })

  it("task_nav_next sends task_uuid from ?task= query param", () => {
    Object.defineProperty(window, "location", {
      value: { pathname: "/projects/5/tasks", search: "?task=abc-def-123", assign: vi.fn() },
      writable: true,
      configurable: true,
    })
    const h = makeHook()
    const cmd = COMMANDS.find(c => c.id === "leader.task.next")!
    h.executeCommand(cmd)
    expect(h.pushEvent).toHaveBeenCalledWith("vim:task-nav", expect.objectContaining({
      task_uuid: "abc-def-123"
    }))
  })

  it("handleEvent vim:task-nav-result navigates when url provided", () => {
    const assignMock = vi.fn()
    Object.defineProperty(window, "location", {
      value: { pathname: "/projects/5/tasks", search: "", assign: assignMock },
      writable: true,
      configurable: true,
    })
    const h = makeHook()
    h.mounted()
    const [_evt, callback] = (h.handleEvent as ReturnType<typeof vi.fn>).mock.calls.find(
      ([evt]: [string]) => evt === "vim:task-nav-result"
    )!
    callback({ url: "/projects/5/tasks?task=next-uuid" })
    expect(assignMock).toHaveBeenCalledWith("/projects/5/tasks?task=next-uuid")
    h.destroyed()
  })

  it("handleEvent vim:task-nav-result does nothing when url is null", () => {
    const assignMock = vi.fn()
    Object.defineProperty(window, "location", {
      value: { pathname: "/projects/5/tasks", search: "", assign: assignMock },
      writable: true,
      configurable: true,
    })
    const h = makeHook()
    h.mounted()
    const [_evt, callback] = (h.handleEvent as ReturnType<typeof vi.fn>).mock.calls.find(
      ([evt]: [string]) => evt === "vim:task-nav-result"
    )!
    callback({ url: null })
    expect(assignMock).not.toHaveBeenCalled()
    h.destroyed()
  })

  it("Space t n is scoped to route_suffix:/tasks (task_nav takes priority on tasks page)", () => {
    const cmd = COMMANDS.find(c =>
      isCommandActive(c) &&
      c.keys.length === 3 &&
      c.keys[0] === "Space" && c.keys[1] === "t" && c.keys[2] === "n"
    )!
    expect(cmd).toBeDefined()
    expect(cmd.id).toBe("leader.task.next")
  })

  it("Space t p is scoped to route_suffix:/tasks (task_nav takes priority on tasks page)", () => {
    const cmd = COMMANDS.find(c =>
      isCommandActive(c) &&
      c.keys.length === 3 &&
      c.keys[0] === "Space" && c.keys[1] === "t" && c.keys[2] === "p"
    )!
    expect(cmd).toBeDefined()
    expect(cmd.id).toBe("leader.task.prev")
  })
})

describe("e open item (list_open_edit)", () => {
  beforeEach(() => { document.body.innerHTML = "" })
  afterEach(() => { document.body.innerHTML = "" })

  const openEditCmd = { id: "list.open_edit", label: "Open item", keys: ["e"], group: "context" as const, action: { kind: "client" as const, name: "list_open_edit" as const }, scope: "feature:vim-list" }

  function makeListWithUrl(url: string): HTMLElement {
    const ul = document.createElement("ul")
    ul.setAttribute("data-vim-list", "")
    const li = document.createElement("li")
    li.setAttribute("data-vim-list-item", "")
    li.dataset.vimItemUrl = url
    ul.appendChild(li)
    document.body.appendChild(ul)
    return li
  }

  it("navigates to data-vim-item-url of focused item", () => {
    const assignMock = vi.fn()
    Object.defineProperty(window, "location", { value: { assign: assignMock }, configurable: true })
    makeListWithUrl("/dm/42")
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0
    h.executeCommand(openEditCmd)
    expect(assignMock).toHaveBeenCalledWith("/dm/42")
  })

  it("no-op when listFocusIndex is -1", () => {
    const assignMock = vi.fn()
    Object.defineProperty(window, "location", { value: { assign: assignMock }, configurable: true })
    makeListWithUrl("/dm/42")
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = -1
    h.executeCommand(openEditCmd)
    expect(assignMock).not.toHaveBeenCalled()
  })

  it("no-op when focused item has no data-vim-item-url", () => {
    const assignMock = vi.fn()
    Object.defineProperty(window, "location", { value: { assign: assignMock }, configurable: true })
    const ul = document.createElement("ul")
    ul.setAttribute("data-vim-list", "")
    const li = document.createElement("li")
    li.setAttribute("data-vim-list-item", "")
    ul.appendChild(li)
    document.body.appendChild(ul)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0
    h.executeCommand(openEditCmd)
    expect(assignMock).not.toHaveBeenCalled()
  })
})

describe("x toggle task done (list_toggle_done)", () => {
  beforeEach(() => { document.body.innerHTML = "" })
  afterEach(() => { document.body.innerHTML = "" })

  const toggleCmd = { id: "list.toggle_done", label: "Toggle done", keys: ["x"], group: "context" as const, action: { kind: "client" as const, name: "list_toggle_done" as const }, scope: "feature:vim-list" }

  function makeTaskItem(taskId: string): HTMLElement {
    const ul = document.createElement("ul")
    ul.setAttribute("data-vim-list", "")
    const li = document.createElement("li")
    li.setAttribute("data-vim-list-item", "")
    li.dataset.vimItemType = "task"
    li.dataset.vimItemId = taskId
    ul.appendChild(li)
    document.body.appendChild(ul)
    return li
  }

  it("pushes vim:toggle-task-done with task_id", () => {
    makeTaskItem("99")
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0
    h.executeCommand(toggleCmd)
    expect(h.pushToList).toHaveBeenCalledWith("vim:toggle-task-done", { task_id: "99" })
  })

  it("no-op when item type is not task", () => {
    const ul = document.createElement("ul")
    ul.setAttribute("data-vim-list", "")
    const li = document.createElement("li")
    li.setAttribute("data-vim-list-item", "")
    li.dataset.vimItemType = "session"
    li.dataset.vimItemId = "5"
    ul.appendChild(li)
    document.body.appendChild(ul)
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = 0
    h.executeCommand(toggleCmd)
    expect(h.pushToList).not.toHaveBeenCalled()
  })

  it("no-op when listFocusIndex is -1", () => {
    makeTaskItem("99")
    const h = makeHook()
    h.mode = "normal"
    h.listFocusIndex = -1
    h.executeCommand(toggleCmd)
    expect(h.pushToList).not.toHaveBeenCalled()
  })

  it("handleEvent vim:toggle-task-done-result updates data-vim-item-done on matching item", () => {
    const li = makeTaskItem("99")
    const h = makeHook()
    h.mounted()
    h.listFocusIndex = 0
    const [_evt, callback] = (h.handleEvent as ReturnType<typeof vi.fn>).mock.calls.find(
      ([evt]: [string]) => evt === "vim:toggle-task-done-result"
    )!
    callback({ task_id: "99", done: true })
    expect(li.dataset.vimItemDone).toBe("true")
    h.destroyed()
  })

  it("handleEvent vim:toggle-task-done-result does nothing when task_id does not match", () => {
    const li = makeTaskItem("99")
    const h = makeHook()
    h.mounted()
    const [_evt, callback] = (h.handleEvent as ReturnType<typeof vi.fn>).mock.calls.find(
      ([evt]: [string]) => evt === "vim:toggle-task-done-result"
    )!
    callback({ task_id: "999", done: true })
    expect(li.dataset.vimItemDone).toBeUndefined()
    h.destroyed()
  })
})
