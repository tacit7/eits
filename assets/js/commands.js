// Command registry and definitions
// Re-exports all command modules and provides getCommands function

import { navigationCommands } from "./hooks/palette_commands/navigation.js"
import { agentCommands } from "./hooks/palette_commands/agents.js"
import { taskCommands } from "./hooks/palette_commands/tasks.js"
import { noteCommands } from "./hooks/palette_commands/notes.js"
import { sessionCommands } from "./hooks/palette_commands/sessions.js"
import { canvasCommands } from "./hooks/palette_commands/canvas.js"
import { projectCommands } from "./hooks/palette_commands/projects.js"

/**
 * Assembles all available commands from all command modules.
 * Each command module exports a function that receives the hook context and returns an array of commands.
 * @param {Object} hook - The hook context (from CommandPalette hook instance)
 * @returns {Array} Flattened array of all commands
 */
export function getCommands(hook) {
  return [
    ...navigationCommands(hook),
    ...agentCommands(hook),
    ...taskCommands(hook),
    ...noteCommands(hook),
    ...sessionCommands(hook),
    ...canvasCommands(hook),
    ...projectCommands(hook),
  ]
}

// Re-export individual command modules for direct access if needed
export {
  navigationCommands,
  agentCommands,
  taskCommands,
  noteCommands,
  sessionCommands,
  canvasCommands,
  projectCommands,
}
