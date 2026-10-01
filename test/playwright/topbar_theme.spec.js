import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'

const topbarSource = readFileSync('assets/vendor/topbar.js', 'utf8')
const appSource = readFileSync('assets/js/app.js', 'utf8')
const navigationSource = appSource.slice(
  appSource.indexOf('// Show progress bar on live navigation and form submits'),
  appSource.indexOf('// Editor layout:')
)

test('navigation progress resolves theme colors before drawing and after theme changes', async ({ page }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setContent('<style>:root { --color-primary: #ff0000; --color-base-content: #ffffff; }</style><main id="main-content"></main>')
  await page.addScriptTag({ content: topbarSource.replace('export default _topbar;', 'window.topbar = _topbar;') })
  await page.addScriptTag({ content: navigationSource })

  for (const [color, expected] of [['#ff0000', [255, 0, 0]], ['#00ff00', [0, 255, 0]]]) {
    await page.evaluate(color => {
      document.documentElement.style.setProperty('--color-primary', color)
      window.dispatchEvent(new CustomEvent('phx:page-loading-start', { detail: { kind: 'navigate' } }))
    }, color)
    await expect(page.locator('canvas')).toBeVisible()
    // Wait past the delayed show so asynchronous Canvas exceptions are captured.
    await page.waitForTimeout(400)
    expect(errors).toEqual([])
    const rendered = await page.evaluate(() => {
      window.topbar.progress(0.5)
      const ctx = document.querySelector('canvas').getContext('2d')
      return { pixel: Array.from(ctx.getImageData(5, 1, 1, 1).data).slice(0, 3), shadow: ctx.shadowColor }
    })
    expect(rendered.pixel).toEqual(expected)
    expect(rendered.shadow).not.toContain('var(')
    expect(rendered.shadow).not.toBe('rgba(0, 0, 0, 0)')
    await page.evaluate(() => window.dispatchEvent(new CustomEvent('phx:page-loading-stop')))
    await expect(page.locator('canvas')).toBeHidden()
  }
})
