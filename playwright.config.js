import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './test/playwright',
  use: {
    baseURL: 'http://localhost:5001',
  },
})
