import { test, expect } from '@playwright/test';

test.describe('Chat message deduplication (@all fix)', () => {
  test('sending a message with @all does not duplicate in the UI', async ({ page }) => {
    // Navigate to chat page
    await page.goto('http://localhost:5002/chat', { waitUntil: 'networkidle' });

    // Wait for chat to load
    await page.waitForSelector('[data-testid="message-list"]', { timeout: 10000 });

    // Get initial message count
    const initialCount = await page.locator('[data-testid="chat-message"]').count();

    // Type a message with @all
    const composerInput = page.locator('textarea[placeholder*="message"]').first();
    await composerInput.fill('Test message @all');

    // Send the message
    const sendButton = page.locator('button:has-text("Send")').first();
    await sendButton.click();

    // Wait for the message to appear
    await page.waitForTimeout(500);

    // Get the new message count
    const newCount = await page.locator('[data-testid="chat-message"]').count();

    // Verify that only one new message was added
    expect(newCount).toBe(initialCount + 1);

    // Verify the message content is present (once)
    const messageElements = await page.locator('text="Test message @all"').count();
    expect(messageElements).toBe(1);
  });

  test('sending a regular message does not get duplicated', async ({ page }) => {
    // Navigate to chat page
    await page.goto('http://localhost:5002/chat', { waitUntil: 'networkidle' });

    // Wait for chat to load
    await page.waitForSelector('[data-testid="message-list"]', { timeout: 10000 });

    // Get initial message count
    const initialCount = await page.locator('[data-testid="chat-message"]').count();

    // Type and send a regular message
    const composerInput = page.locator('textarea[placeholder*="message"]').first();
    const testMessage = `Regular message ${Date.now()}`;
    await composerInput.fill(testMessage);

    // Send the message
    const sendButton = page.locator('button:has-text("Send")').first();
    await sendButton.click();

    // Wait for the message to appear
    await page.waitForTimeout(500);

    // Get the new message count
    const newCount = await page.locator('[data-testid="chat-message"]').count();

    // Verify that only one new message was added
    expect(newCount).toBe(initialCount + 1);

    // Verify the message appears exactly once
    const messageElements = await page.locator(`text="${testMessage}"`).count();
    expect(messageElements).toBe(1);
  });
});
