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
  it("lowercases single character keys", () => {
    const e = new KeyboardEvent("keydown", { key: "S" })
    expect(keyFromEvent(e)).toBe("s")
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
    h.showWhichKey("t")
    expect(document.getElementById("vim-nav-which-key")).toBeNull()
    vi.advanceTimersByTime(300)
    expect(document.getElementById("vim-nav-which-key")).not.toBeNull()
    h.hideWhichKey()
  })

  it("hideWhichKey before 300ms cancels the timer (no overlay appears)", () => {
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    h.showWhichKey("t")
    h.hideWhichKey()
    vi.advanceTimersByTime(300)
    expect(document.getElementById("vim-nav-which-key")).toBeNull()
  })

  it("hideWhichKey removes DOM element if overlay was rendered", () => {
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    h.showWhichKey("t")
    vi.advanceTimersByTime(300)
    expect(document.getElementById("vim-nav-which-key")).not.toBeNull()
    h.hideWhichKey()
    expect(document.getElementById("vim-nav-which-key")).toBeNull()
  })

  it("second showWhichKey call resets the timer", () => {
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    h.showWhichKey("t")
    vi.advanceTimersByTime(200)
    h.showWhichKey("n")
    vi.advanceTimersByTime(100)  // only 100ms since second call — should not render yet
    expect(document.getElementById("vim-nav-which-key")).toBeNull()
    vi.advanceTimersByTime(200)  // 300ms since second call — should render
    expect(document.getElementById("vim-nav-which-key")).not.toBeNull()
    h.hideWhichKey()
  })

  it("clearSequence hides which-key", () => {
    const h = makeHook()
    h.pushEventToShell = vi.fn()
    h.showWhichKey("g")
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
    h._renderWhichKey("z")
    expect(document.getElementById("vim-nav-which-key")).toBeNull()
  })

  it("which-key renders overlay for active prefix commands", () => {
    const h = makeHook()
    h._renderWhichKey("g")
    expect(document.getElementById("vim-nav-which-key")).not.toBeNull()
    h.hideWhichKey()
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
