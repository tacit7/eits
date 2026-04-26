import { describe, it, expect, beforeEach, vi } from "vitest"
import { isEditableTarget, keyFromEvent, matchesKnownBindingOrPrefix, VimNav } from "./vim_nav"

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

  it("prepends project path when relative + project context exists", () => {
    const h = makeHook({ projectPath: "/projects/42" })
    expect(h.buildPath("tasks", true)).toBe("/projects/42/tasks")
  })

  it("strips trailing/leading slashes when joining project path", () => {
    const h = makeHook({ projectPath: "/projects/42/" })
    expect(h.buildPath("/tasks", true)).toBe("/projects/42/tasks")
  })

  it("falls back to /workspace/<segment> for known workspace routes", () => {
    const h = makeHook()
    expect(h.buildPath("tasks", true)).toBe("/workspace/tasks")
    expect(h.buildPath("notes", true)).toBe("/workspace/notes")
    expect(h.buildPath("sessions", true)).toBe("/workspace/sessions")
  })

  it("returns null for relative agents with no project (no /workspace/agents route)", () => {
    const h = makeHook()
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
