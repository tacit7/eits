import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'

// Build the CSS with `mix tailwind eye_in_the_sky` before running this spec.
// Render the production modal directly so no live agent or message delivery is needed.
const modalSource = readFileSync('assets/js/hooks/floating_chat_modal.js', 'utf8')
const css = readFileSync('priv/static/assets/css/app.css', 'utf8')

for (const viewport of [{ width: 1280, height: 720 }, { width: 390, height: 664 }, { width: 844, height: 390 }]) {
  test(`long agent chats keep controls reachable at ${viewport.width}x${viewport.height}`, async ({ page }) => {
    await page.setViewportSize(viewport)
    await page.setContent('<html data-theme="mocha"><body></body></html>')
    await page.addStyleTag({ content: css })
    await page.addScriptTag({ content: modalSource.replace('export class', 'class') + '\nwindow.FloatingChatModal = FloatingChatModal' })
    await page.evaluate(() => {
      window.modal = new window.FloatingChatModal({
        id: 'viewport-chat', title: 'Team agent', initials: 'TA',
        onSend: body => { window.sentBody = body },
        onClose: () => window.modal.destroy(),
      }).create()
      window.modal.setMessages(Array.from({ length: 100 }, (_, i) => ({ sender_role: 'agent', body: `Message ${i}: ` + 'Long conversation details. '.repeat(20) })))
    })
    const assertControlsFit = async () => {
      for (const id of ['close', 'input', 'send']) {
        const box = await page.locator(`#viewport-chat-${id}`).boundingBox()
        expect(box.y).toBeGreaterThanOrEqual(0)
        expect(box.x).toBeGreaterThanOrEqual(0)
        expect(box.y + box.height).toBeLessThanOrEqual(page.viewportSize().height)
        expect(box.x + box.width).toBeLessThanOrEqual(page.viewportSize().width)
      }
    }
    await assertControlsFit()
    const history = page.locator('#viewport-chat-messages')
    expect(await history.evaluate(el => el.scrollHeight > el.clientHeight && el.clientHeight > 0)).toBe(true)
    await history.evaluate(el => { el.scrollTop = 0 })
    await assertControlsFit()
    await page.setViewportSize({ width: viewport.width, height: viewport.height - 80 })
    await assertControlsFit()
    await page.locator('#viewport-chat-input').fill('Follow up')
    await page.locator('#viewport-chat-send').click()
    expect(await page.evaluate(() => window.sentBody)).toBe('Follow up')
    await page.locator('#viewport-chat-close').click()
    await expect(page.locator('#viewport-chat')).toHaveCount(0)
  })
}
