import _components from "virtual:live-svelte-components"
import {getRender} from "live_svelte"

// Strip directory prefixes from component keys so they match the bare names
// used in Elixir templates (e.g. "components/tabs/TasksTab" -> "TasksTab").
const components = Object.fromEntries(
  Object.entries(_components).map(([key, comp]) => [key.split("/").pop(), comp])
)

export const render = getRender(components)
