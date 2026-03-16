// test/playwright/config_guide_chat.spec.js
import { test, expect } from '@playwright/test'

test.describe('Config Guide chat button', () => {
  test.beforeEach(async ({ page }) => {
    // Mock the agent spawn endpoint so tests don't require a live Claude API
    await page.route('/api/v1/agents', async route => {
      await route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          message: 'Agent spawned',
          agent_id: 'test-agent-uuid',
          session_id: 1,
          session_uuid: 'test-session-uuid-1234',
        }),
      })
    })
  })

  test('Config Guide button renders on /config', async ({ page }) => {
    await page.goto('/config')
    const btn = page.locator('#config-guide-chat-btn')
    await expect(btn).toBeVisible()
    await expect(btn).toContainText('Config Guide')
  })

  test('clicking button creates chat modal', async ({ page }) => {
    await page.goto('/config')

    await page.click('#config-guide-chat-btn')

    // Modal should appear
    await expect(page.locator('#config-guide-chat-modal')).toBeVisible({ timeout: 5000 })
    // Loading skeleton appears while waiting for history
    await expect(page.locator('#config-guide-loading')).toBeVisible()
  })

  test('double-clicking button does not create two modals', async ({ page }) => {
    await page.goto('/config')

    await page.click('#config-guide-chat-btn')
    await page.click('#config-guide-chat-btn')

    const modals = await page.locator('#config-guide-chat-modal').count()
    expect(modals).toBe(1)
  })

  test('close button removes modal and re-enables button', async ({ page }) => {
    await page.goto('/config')

    await page.click('#config-guide-chat-btn')
    await expect(page.locator('#config-guide-chat-modal')).toBeVisible({ timeout: 5000 })

    await page.click('#config-guide-close')

    await expect(page.locator('#config-guide-chat-modal')).not.toBeVisible()
    await expect(page.locator('#config-guide-chat-btn')).toBeEnabled()
  })

  test('clicking button again after close opens a fresh modal', async ({ page }) => {
    await page.goto('/config')

    await page.click('#config-guide-chat-btn')
    await expect(page.locator('#config-guide-chat-modal')).toBeVisible({ timeout: 5000 })
    await page.click('#config-guide-close')
    await expect(page.locator('#config-guide-chat-modal')).not.toBeVisible()

    await page.click('#config-guide-chat-btn')
    await expect(page.locator('#config-guide-chat-modal')).toBeVisible({ timeout: 5000 })
  })
})
