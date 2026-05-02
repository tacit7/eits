import { navigationCommands } from "./navigation.js"
import { agentCommands } from "./agents.js"
import { taskCommands } from "./tasks.js"
import { noteCommands } from "./notes.js"
import { sessionCommands } from "./sessions.js"
import { canvasCommands } from "./canvas.js"
import { projectCommands } from "./projects.js"

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
