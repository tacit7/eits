// test/playwright/note_editor_test.js
const { test, expect, chromium } = require('@playwright/test')

const BASE_URL = 'http://localhost:5000'

test.describe('Note inline editor', () => {
  let browser, page

  test.beforeAll(async () => {
    browser = await chromium.launch()
  })

  test.afterAll(async () => {
    await browser.close()
  })

  test.beforeEach(async () => {
    page = await browser.newPage()
    // Dev-only: set session cookie without WebAuthn, then navigate to notes
    await page.goto(`${BASE_URL}/dev/test-login?user_id=2`, { waitUntil: 'load' })
    await page.goto(`${BASE_URL}/projects/1/notes`, { waitUntil: 'domcontentloaded' })
    // Wait for LiveView socket to connect (root element gets phx-connected class)
    await page.waitForSelector('.phx-connected', { timeout: 10000 })
    // Wait for the notes list to render
    await page.waitForSelector('[phx-click="edit_note"]', { timeout: 10000 })
  })

  test.afterEach(async () => {
    await page.close()
  })

  test('1. notes page shows Edit button per note', async () => {
    const editButtons = await page.locator('[phx-click="edit_note"]').count()
    expect(editButtons).toBeGreaterThan(0)
  })

  test('2. clicking Edit mounts CodeMirror with note content', async () => {
    await page.locator('[phx-click="edit_note"]').first().click()
    const editor = page.locator('[phx-hook="NoteEditor"]').first()
    await expect(editor).toBeVisible({ timeout: 3000 })
    await expect(editor.locator('.cm-content')).toBeVisible()
  })

  test('3. Cmd+S saves and shows updated content in markdown', async () => {
    await page.locator('[phx-click="edit_note"]').first().click()
    const editor = page.locator('[phx-hook="NoteEditor"]').first()
    await expect(editor).toBeVisible({ timeout: 3000 })

    await editor.locator('.cm-content').click()
    await page.keyboard.press('Meta+a')
    const uniqueText = `Test save ${Date.now()}`
    await page.keyboard.type(uniqueText)
    await page.keyboard.press('Meta+s')

    await expect(editor).not.toBeVisible({ timeout: 3000 })
    await expect(page.locator('[id^="note-body-"]').first()).toContainText(uniqueText, { timeout: 3000 })
  })

  test('4. Escape cancels edit and restores markdown renderer', async () => {
    await page.locator('[phx-click="edit_note"]').first().click()
    const editor = page.locator('[phx-hook="NoteEditor"]').first()
    await expect(editor).toBeVisible({ timeout: 3000 })

    await page.keyboard.press('Escape')

    await expect(editor).not.toBeVisible({ timeout: 3000 })
    await expect(page.locator('[id^="note-body-"]').first()).toBeVisible()
  })

  test('5. clicking Edit on note B while editing note A switches editors', async () => {
    const editButtons = page.locator('[phx-click="edit_note"]')
    if (await editButtons.count() < 2) test.skip()

    await editButtons.nth(0).click()
    await expect(page.locator('[phx-hook="NoteEditor"]').first()).toBeVisible({ timeout: 3000 })

    const secondNoteId = await editButtons.nth(1).getAttribute('phx-value-note_id')
    await editButtons.nth(1).click()

    await expect(page.locator(`#note-editor-${secondNoteId}`)).toBeVisible({ timeout: 3000 })
  })
})
