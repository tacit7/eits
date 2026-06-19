# Playwright E2E Test Plan: Session Functionality

## Overview
This document outlines the Playwright e2e test coverage plan for session functionality in the EITS web application. Currently, Playwright is not installed in the project (see setup requirements below).

## Setup Requirements

Before implementing these tests, Playwright must be installed:

```bash
cd assets/
npm install -D @playwright/test
```

Then create Playwright configuration:

```bash
npx playwright install
```

## Test File Location
- Location: `test/e2e/` (or `assets/e2e/` if using Node-based Playwright)
- Framework: Playwright (JavaScript/TypeScript)
- Browser: Chromium (primary), Firefox and WebKit as secondary

## Test Scenarios

### 1. Session Listing Page (`/projects/:id/sessions`)

#### Test 1.1: Session List Renders
- **Setup**: Create project via API/seed
- **Action**: Navigate to `http://localhost:5001/projects/{project_id}/sessions`
- **Expected**: 
  - Page title shows "Sessions"
  - "New Agent" button visible
  - Session list container rendered

#### Test 1.2: Session Rows Display Agent Data
- **Setup**: Create project with 2-3 sessions/agents
- **Action**: Navigate to sessions page
- **Expected**:
  - Each session row displays: agent name, model, status badge
  - Session count matches database
  - Rows are clickable/interactive

#### Test 1.3: Session Filtering by Status
- **Setup**: Create sessions with mixed statuses (running, idle, completed)
- **Action**: 
  1. Navigate to sessions page
  2. Click status filter dropdown
  3. Select "Running" 
- **Expected**:
  - Only running sessions appear
  - Count reflects filtered results
  - Filter state persists on reload

#### Test 1.4: Session Search
- **Setup**: Create sessions with distinct names
- **Action**:
  1. Navigate to sessions page
  2. Type session name in search box
  3. Press Enter or wait for debounce
- **Expected**:
  - List filters to matching sessions in real-time
  - Partial name matches work
  - Search is case-insensitive

### 2. New Session Creation (`/projects/:id/sessions`)

#### Test 2.1: New Agent Modal Opens
- **Setup**: Navigate to sessions page
- **Action**: Click "New Agent" button
- **Expected**:
  - Modal/drawer opens with form
  - Form fields visible: model selector, description textarea
  - Cancel button closes modal

#### Test 2.2: Create Session Form Validation
- **Setup**: Modal is open
- **Action**: Click submit without filling required fields
- **Expected**:
  - Validation error messages appear
  - Form is not submitted
  - Modal remains open

#### Test 2.3: Create Session Successfully
- **Setup**: Modal is open
- **Action**:
  1. Select model from dropdown (e.g., "claude-sonnet-4-6")
  2. Enter description text
  3. Click "Create" button
- **Expected**:
  - Modal closes
  - New session appears in list (top or sorted position)
  - Page does not require full reload
  - Session is queryable via API within 1-2s

### 3. Session Detail / Interactions

#### Test 3.1: Click Session Row
- **Setup**: Sessions exist in list
- **Action**: Click on a session row
- **Expected**:
  - Navigates to session detail page (or opens side panel)
  - Session details displayed: created_at, status timeline, agent info
  - Breadcrumbs or back button available

#### Test 3.2: Session Status Updates
- **Setup**: Session is running (mock via API if needed)
- **Action**: Keep page open and monitor status badge
- **Expected**:
  - Status badge updates in real-time (no manual refresh)
  - Timestamp updates reflect live data
  - Page does not flicker or scroll jump

### 4. Workspace Sessions Page

#### Test 4.1: Workspace Sessions List Renders
- **Setup**: Authenticated user with multiple projects
- **Action**: Navigate to `http://localhost:5001/workspace/sessions`
- **Expected**:
  - "Across all projects" badge visible
  - Sessions from all user projects displayed
  - Project name shown per session for context

#### Test 4.2: Filter Workspace Sessions by Project
- **Setup**: Sessions from multiple projects visible
- **Action**: Click project filter dropdown and select one project
- **Expected**:
  - List filters to selected project sessions only
  - Count updates
  - Project selection persists

## Test Infrastructure

### Playwright Config
```javascript
// playwright.config.ts (at project root or assets/)
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './test/e2e',
  webServer: {
    command: 'PORT=5002 DISABLE_AUTH=true mix phx.server',
    url: 'http://localhost:5002',
    reuseExistingServer: process.env.CI !== 'true',
    timeout: 30000,
  },
  use: {
    baseURL: 'http://localhost:5002',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
  ],
});
```

### Test Helpers
- **Authentication**: Use `DISABLE_AUTH=true` mode or mock login endpoint
- **Database**: Use Ecto setup/teardown fixtures for test data
- **Timeouts**: Set reasonable waits (2-5s) for DOM elements and network requests
- **Selectors**: Use `data-testid` attributes on key elements for stable selectors

## Coverage Goals

- **Happy path**: Session list → filter → create new session
- **Error cases**: Validation errors, API failures, network latency
- **Accessibility**: Tab navigation, screen reader compatibility
- **Performance**: Page load time <2s, list render <500ms

## Running Tests

Once Playwright is installed:

```bash
# Run all tests
npx playwright test

# Run with UI mode (watch mode)
npx playwright test --ui

# Run specific test
npx playwright test session_test.spec.js

# Run single test
npx playwright test -g "Session Listing Page"

# Report
npx playwright show-report
```

## Known Blockers

- Playwright requires Node.js test runner, not Elixir ExUnit
- DISABLE_AUTH mode required for e2e tests (no login flow)
- Vite/CSS may take 5-10s to compile on first load
- Database cleanup between tests requires careful fixture setup

## Future Enhancements

1. Add visual regression testing (screenshots)
2. Add accessibility (a11y) checks with `@axe-core/playwright`
3. Performance monitoring with `@traceability/playwright`
4. CI integration (GitHub Actions, etc.)
5. Load testing with concurrent sessions
