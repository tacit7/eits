# Command Palette

The Command Palette provides quick navigation, command execution, and task creation through a keyboard-accessible interface. Access via `Cmd/Ctrl + K` anywhere in the app.

**Implementation:**
- Hook: `assets/js/app.js` (CommandPalette hook)
- Registry: `assets/js/app.js` (CommandRegistry)
- Component: `lib/eye_in_the_sky_web_web/components/layouts/app.html.heex`

---

## Command Registry

The `CommandRegistry` defines all available commands with categorization and filtering rules.

**Command structure:**
```javascript
{
  id: "command-id",
  label: "Command Name",
  icon: "hero-icon-name",
  category: "Navigation|Quick Create|Search",
  action: (state) => { /* handler */ },
  when: (state) => boolean, // Show only if condition true
  submenu: [] // Optional submenu commands
}
```

**Categories:**
- **Navigation** — Navigate to pages/sections
- **Quick Create** — Create new resources (agents, tasks, notes)
- **Search** — Find resources by name/description

---

## Command Groups

Commands are organized into groups that render in priority order:

1. **Current Project** — Project-scoped navigation (shown only when inside `/projects/:id`)
2. **Workspace** — Global workspace navigation
3. **Projects** — Project management
4. **Tasks** — Task-related commands
5. **Insights** — Analytics and reporting
6. **Knowledge** — Documentation and references
7. **Communication** — Chat and messaging
8. **System** — Settings and configuration

---

## Navigation Commands

### Current Project Commands

When navigating within a project (e.g., `/projects/123/sessions`), a "Current Project" group appears at the top with quick access to all project pages. Each command shows the project name as a hint.

Available current project commands:
- **Sessions** — Navigate to project Sessions page
- **Tasks** — Navigate to project Tasks page
- **Kanban** — Navigate to project Kanban board
- **Notes** — Navigate to project Notes page
- **Agents** — Navigate to project Agents page
- **Prompts** — Navigate to project Prompts page
- **Skills** — Navigate to project Skills page
- **Files** — Navigate to project Files page
- **Teams** — Navigate to project Teams page
- **Configuration** — Navigate to project Configuration page

**Implementation:**
- Detected via URL pattern: `/projects/:id`
- Only rendered when URL matches current project context
- Uses project ID and name from dataset attribute

### Workspace Navigation

#### Go to Session
- **ID:** `go-sessions`
- **Group:** Workspace
- **Feature:** Submenu with async session fetch
- **Project scoping:** Filters sessions to current project when in project context
- **Behavior:**
  - Shows loading state while fetching sessions
  - Displays session name or description in submenu
  - Ordered by last_activity_at (newest first)
  - Fetches all non-archived sessions
  - Click to navigate to session's DM page

#### Go to Project
- **ID:** `go-projects`
- **Group:** Workspace
- **Behavior:** Lists all active projects with quick navigation to project overview

---

## Quick Create Commands

### New Agent
- **ID:** `new-agent`
- **Label:** "New Agent"
- **Action:** Opens new agent drawer with model/effort selection

### New Chat
- **ID:** `new-chat`
- **Label:** "Start new chat"
- **Action:** Creates new session and navigates to DM page

### Create Note
- **ID:** `create-note`
- **Label:** "Create note"
- **Action:** Opens note creation form (project-scoped if available)

### Create Task
- **ID:** `create-task`
- **Label:** "Create task"
- **Action:** Opens task creation dialog
- **Scoping:** Task automatically scoped to current project via `sidebar_project` assign
- **Fields:** Title, description, project, tags

---

## Search Interface

### Stack Navigation
- Commands organized in hierarchical stack
- Parent command shows breadcrumb at top of palette
- Use Escape to pop back to parent menu
- Use Backspace to go back from submenu

### Fuzzy Matching
- Searches command labels and category names
- Partial matching supported (non-consecutive character matching)
- Highlights matching characters in results
- Case-insensitive search

### Breadcrumb
- Shows current navigation context
- Appears between search input and results
- Indicates nested submenu position

---

## Tab Activation

When exactly one search result is visible, pressing Tab automatically activates that item without requiring Enter. This provides quick single-result navigation.

---

## Mobile Support

- Command palette available on mobile via Cmd/Ctrl + K
- Optimized for touch: larger tap targets, slower animations
- Bottom sheet layout on small screens (alternative to center modal)
- Quick-create commands prioritized in mobile context

---

## Performance Considerations

**Async loading:**
- "Go to Session" submenu fetches sessions asynchronously
- Shows loading indicator while fetching
- Cache sessions for 30 seconds to prevent repeated API calls

**Search:**
- Debounced fuzzy search (100ms)
- Results limited to top 10 matches
- Highlight rendering optimized for fast re-renders

---

## File Locations

| Component | Path |
|-----------|------|
| Hook | `assets/js/hooks/command_palette.js` |
| Navigation Commands | `assets/js/hooks/palette_commands/navigation.js` |
| Current Project Commands | `assets/js/hooks/palette_commands/navigation.js` |
| Layout Component | `lib/eye_in_the_sky_web_web/components/layouts/app.html.heex` |
| API (sessions fetch) | `lib/eye_in_the_sky_web_web/controllers/api/v1/session_controller.ex` |
