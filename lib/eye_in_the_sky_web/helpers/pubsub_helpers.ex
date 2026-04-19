defmodule EyeInTheSkyWeb.Helpers.PubSubHelpers do
  @moduledoc """
  Convenience wrappers for common Phoenix.PubSub subscriptions used across LiveViews.

  Call these inside `if connected?(socket) do` blocks in `mount/3`.

  ## Channel Map

  Every broadcast topic in the system, with payloads, broadcaster, and subscribers.

  ### `"tasks"`

  Broadcast by `EyeInTheSky.Tasks` on every task create/update/delete.

  | Payload          | Broadcaster                | Subscribers                         |
  |------------------|----------------------------|-------------------------------------|
  | `:tasks_changed` | `EyeInTheSky.Tasks`     | `DMLive` (via `subscribe_tasks/0`)  |

  ### `"tasks:<project_id>"`

  Same as `"tasks"` but scoped to a project. Only broadcast when the task has
  a non-nil `project_id`. Reserved for project-scoped views; no subscriber yet.

  ### `"agents"`

  Broadcast by `EyeInTheSky.Agents` on agent CRUD.

  | Payload                      | Event          |
  |------------------------------|----------------|
  | `{:agent_created, agent}`    | Agent inserted |
  | `{:agent_updated, agent}`    | Agent updated  |
  | `{:agent_deleted, agent}`    | Agent deleted  |

  Subscribers: `subscribe_agents/0`.

  ### `"agent:working"`

  Broadcast by `AgentWorker` on idle/active transitions.

  | Payload                        | Broadcaster         | Meaning                 |
  |--------------------------------|---------------------|-------------------------|
  | `{:agent_working, %Session{}}` | `AgentWorkerEvents` | SDK started processing  |
  | `{:agent_stopped, %Session{}}` | `AgentWorkerEvents` | SDK idle / error / done |

  Subscribers: `subscribe_agent_working/0` — `ChatLive`, `DMLive`.

  ### `"session:<session_id>"`

  Per-session events. `session_id` is the **integer** PK from the `sessions`
  table (not the UUID).

  | Payload                                       | Broadcaster            | Meaning                  |
  |-----------------------------------------------|------------------------|--------------------------|
  | `{:new_message, %Message{}}`                  | `Messages.Broadcaster` | New message polled from DB |
  | `{:claude_response, session_ref, parsed}`     | `AgentWorker`          | Claude CLI output chunk  |
  | `{:claude_complete, session_ref, exit_code}`  | `AgentWorker`          | Claude CLI process exited |

  Subscribers: `subscribe_session/1` — `DMLive`, `FloatingChatLive`.

  ### `"session:<session_id>:status"`

  Session status change events. `session_id` here is the UUID string.

  | Payload                                  | Broadcaster     |
  |------------------------------------------|-----------------|
  | `{:session_status, session_id, status}`  | `AgentWorker`   |

  Use `EyeInTheSky.Events.subscribe_*` helpers.

  ### `"dm:<session_id>:stream"`

  Real-time streaming deltas from `AgentWorker`. `session_id` is the integer
  session PK.

  | Payload                              | Meaning                            |
  |--------------------------------------|------------------------------------|
  | `{:stream_delta, :text, text}`       | Incremental text chunk             |
  | `{:stream_replace, :text, text}`     | Full accumulated text so far       |
  | `{:stream_delta, :tool_use, name}`   | Tool call started                  |
  | `{:stream_replace, :tool_use, name}` | Tool block complete                |
  | `{:stream_delta, :thinking, nil}`    | Thinking block in progress         |
  | `{:stream_replace, :thinking, text}` | Thinking block complete            |
  | `:stream_clear`                      | Stream ended / cleared             |

  Subscribers: `subscribe_dm_stream/1` — `DMLive`.

  ### `"dm:<session_id>:queue"`

  Queue state updates from `AgentWorker`. `session_id` is the integer session PK.

  | Payload                   | Meaning                    |
  |---------------------------|----------------------------|
  | `{:queue_updated, queue}` | Queued prompt list changed |

  Subscribers: `subscribe_dm_queue/1` — `DMLive`.

  ### `"channel:<channel_id>:messages"`

  New messages on a chat channel. Broadcast by `Messages.Broadcaster` (polling)
  and by `ChatLive` when a user sends a message.

  | Payload                      | Broadcaster                        |
  |------------------------------|------------------------------------|
  | `{:new_message, %Message{}}` | `Messages.Broadcaster`, `ChatLive` |

  Subscribers: `subscribe_channel_messages/1` — `ChatLive`.

  ### `"notifications"`

  Broadcast by `EyeInTheSky.Notifications`.

  | Payload                             | Event                    |
  |-------------------------------------|--------------------------|
  | `{:notification_created, notif}`    | New notification         |
  | `{:notification_read, notif}`       | Notification marked read |
  | `{:notifications_updated, payload}` | Bulk update              |

  Subscribers: `FloatingChatLive` (subscribes directly, not via helper).

  ### `"teams"`

  Broadcast by `EyeInTheSky.Teams` on team/member changes.

  | Payload                    | Event          |
  |----------------------------|----------------|
  | `{:team_created, team}`    | Team created   |
  | `{:team_deleted, team}`    | Team deleted   |
  | `{:member_joined, member}` | Member added   |
  | `{:member_updated, member}`| Member updated |
  | `{:member_left, member}`   | Member removed |

  Use `EyeInTheSky.Events.subscribe_*` helpers.
  """

  alias EyeInTheSky.Events

  @doc "Subscribe to agent lifecycle events (created/updated/deleted)."
  def subscribe_agents, do: Events.subscribe_agents()

  @doc "Subscribe to agent working/stopped status events."
  def subscribe_agent_working, do: Events.subscribe_agent_working()

  @doc "Subscribe to task change events."
  def subscribe_tasks, do: Events.subscribe_tasks()

  @doc "Subscribe to session-specific events for the given session id."
  def subscribe_session(session_id), do: Events.subscribe_session(session_id)

  @doc "Subscribe to live-stream deltas for the given session id."
  def subscribe_dm_stream(session_id), do: Events.subscribe_dm_stream(session_id)

  @doc "Subscribe to the queued-prompt updates for the given session id."
  def subscribe_dm_queue(session_id), do: Events.subscribe_dm_queue(session_id)

  @doc "Subscribe to new messages broadcast on the given channel."
  def subscribe_channel_messages(channel_id), do: Events.subscribe_channel_messages(channel_id)

  @doc "Unsubscribe from new messages broadcast on the given channel."
  def unsubscribe_channel_messages(channel_id), do: Events.unsubscribe_channel_messages(channel_id)
end
