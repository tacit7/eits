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
})
