import { describe, it, expect } from "vitest"
import { isEditableTarget, keyFromEvent, matchesKnownBindingOrPrefix } from "./vim_nav"

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
