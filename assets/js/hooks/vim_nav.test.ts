import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { isEditableTarget, keyFromEvent, matchesKnownBindingOrPrefix, VimNav } from "./vim_nav"
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
