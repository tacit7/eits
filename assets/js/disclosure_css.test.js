import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

describe('eits disclosure CSS', () => {
  it('collapses checkbox-backed disclosure content until checked', () => {
    const css = readFileSync(join(process.cwd(), 'css/app.css'), 'utf8')

    expect(css).toContain(
      '.eits-disclosure > input[type="checkbox"]:not(:checked) ~ .eits-disclosure__content'
    )
    expect(css).toContain(
      '.eits-disclosure > input[type="checkbox"]:checked ~ .eits-disclosure__content'
    )
  })

  it('keeps disclosure inputs clickable so rows can open inline content', () => {
    const css = readFileSync(join(process.cwd(), 'css/app.css'), 'utf8')
    const rule = css.match(/\.eits-disclosure > input\[type="checkbox"\]\s*\{[^}]+\}/)?.[0]

    expect(rule).toContain('inset: 0')
    expect(rule).toContain('cursor: pointer')
    expect(rule).not.toContain('pointer-events: none')
  })

  it('hides dropdown menus until their trigger is active', () => {
    const css = readFileSync(join(process.cwd(), 'css/app.css'), 'utf8')

    expect(css).toContain('.eits-dropdown .eits-menu')
    expect(css).toContain('.eits-dropdown:focus-within .eits-menu')
  })
})
