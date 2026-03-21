import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './test/playwright',
  testMatch: ['**/*.spec.js', '**/*_test.js'],
  use: {
    baseURL: 'http://localhost:5001',
  },
})
