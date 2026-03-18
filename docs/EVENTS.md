# Events

`EyeInTheSkyWeb.Events` (`lib/eye_in_the_sky_web/events.ex`) is the single gateway for all Phoenix.PubSub broadcasts and subscriptions in the app.

**Rule: never call `Phoenix.PubSub` directly.** Always use a named function from this module.

```elixir
# GOOD
EyeInTheSkyWeb.Events.agent_updated(agent)
EyeInTheSkyWeb.Events.subscribe_session(session_id)

# BAD
Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "agents", {:agent_updated, agent})
Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{session_id}")
```

---

## Topics

| Topic | Subscribe helper | Broadcasters | Subscribers |
|---|---|---|---|
| `"agents"` | `subscribe_agents/0` | `Agents`, `SessionController` | Sidebar, DMLive, session pages |
| `"agent:working"` | `subscribe_agent_working/0` | `WorkerEvents`, `SessionWorker`, `SessionController` | ChatLive, DMLive |
| `"session:<id>"` | `subscribe_session/1` | `Messages`, `Messages.Broadcaster`, `SessionWorker`, `SessionController`, `MessagingController`, `GiteaWebhookController` | DMLive, FabHook |
| `"session:<id>:status"` | `subscribe_session_status/1` | `SessionWorker` | DMLive |
| `"dm:<id>:stream"` | `subscribe_dm_stream/1` | `AgentWorker`, `WorkerEvents` | DMLive |
| `"dm:<id>:queue"` | `subscribe_dm_queue/1` | `WorkerEvents` | DMLive |
| `"channel:<id>:messages"` | `subscribe_channel_messages/1` | `Messages`, `Messages.Broadcaster`, `ChatLive`, `MessagingController` | ChatLive |
| `"tasks"` | `subscribe_tasks/0` | `Tasks`, `Tasks.Poller` | Overview, DMLive |
| `"tasks:<project_id>"` | `subscribe_project_tasks/1` | `Tasks` | Kanban |
| `"notifications"` | `subscribe_notifications/0` | `Notifications` | FabHook |
| `"teams"` | `subscribe_teams/0` | `Teams` | TeamLive |
| `"settings"` | `subscribe_settings/0` | `Settings` | OverviewSettings |
| `"scheduled_jobs"` | `subscribe_scheduled_jobs/0` | Workers, `JobHelper` | JobsLive |
| `"session_lifecycle"` | `subscribe_session_lifecycle/0` | `WorkerEvents` | Teams.Subscriber |
| `"tool_approvals"` | `subscribe_tool_approvals/0` | _(not yet implemented)_ | _(not yet implemented)_ |

---

## Payloads by topic

### `"agents"`

| Payload | Broadcaster | Meaning |
|---|---|---|
| `{:agent_created, agent}` | `Agents` | Agent identity record inserted |
| `{:agent_updated, agent}` | `Agents`, `SessionController` | Agent/session record updated |
| `{:agent_deleted, agent}` | `Agents` | Agent identity record removed |
| `{:agent_stopped, session}` | `SessionController` | Session terminal state (REST API form) |

### `"agent:working"`

Two payload shapes exist for historical reasons — see [Known inconsistency](#known-inconsistency) below.

| Payload | Source | Meaning |
|---|---|---|
| `{:agent_working, session_ref, session_int_id}` | Workers | Agent started processing (string ref + integer id) |
| `{:agent_stopped, session_ref, session_int_id}` | Workers | Agent went idle/errored (string ref + integer id) |
| `{:agent_working, session}` | REST API | Agent started processing (session struct) |
| `{:agent_stopped, session}` | REST API | Agent stopped (session struct) |

### `"session:<id>"` _(id = integer session PK)_

| Payload | Meaning |
|---|---|
| `{:new_message, message}` | New outbound message persisted |
| `{:new_dm, message}` | DM injected from REST API or Gitea webhook |
| `{:claude_response, session_ref, parsed}` | Claude CLI output chunk |
| `{:claude_complete, session_ref, exit_code}` | Claude CLI process exited |
| `{:tool_use, tool_name, tool_input}` | Tool pre-event (before execution) |
| `{:tool_result, tool_name, error?}` | Tool post-event (after execution) |

### `"session:<id>:status"` _(id = UUID string)_

| Payload | Meaning |
|---|---|
| `{:session_status, session_id, status}` | Status changed to `:working` or `:idle` |

### `"dm:<id>:stream"` _(id = integer session PK)_

| Payload | Meaning |
|---|---|
| `{:stream_delta, :text, text}` | Incremental text chunk |
| `{:stream_replace, :text, text}` | Full accumulated text so far |
| `{:stream_delta, :tool_use, name}` | Tool call started |
| `{:stream_replace, :tool_use, name}` | Tool block complete |
| `{:stream_delta, :thinking, nil}` | Thinking block in progress |
| `{:stream_replace, :thinking, text}` | Thinking block complete |
| `:stream_clear` | Stream ended or display cleared |
| `{:agent_error, provider_id, session_id, reason}` | Error on stream |

### `"dm:<id>:queue"` _(id = integer session PK)_

| Payload | Meaning |
|---|---|
| `{:queue_updated, queue}` | Queued prompt list changed |

### `"channel:<id>:messages"`

| Payload | Meaning |
|---|---|
| `{:new_message, message}` | New message on the channel |

### `"tasks"`

| Payload | Meaning |
|---|---|
| `:tasks_changed` | Any task create/update/delete |

### `"tasks:<project_id>"`

| Payload | Meaning |
|---|---|
| `:tasks_changed` | Task change scoped to this project |

### `"notifications"`

| Payload | Meaning |
|---|---|
| `{:notification_created, notification}` | New notification |
| `{:notification_read, id}` | Notification marked read |
| `{:notifications_updated, nil}` | Bulk read (mark all read) |

### `"teams"`

| Payload | Meaning |
|---|---|
| `{:team_created, team}` | Team created |
| `{:team_deleted, team}` | Team deleted |
| `{:member_joined, member}` | Member added |
| `{:member_updated, member}` | Member updated |
| `{:member_left, member}` | Member removed |

### `"settings"`

| Payload | Meaning |
|---|---|
| `{:settings_changed, key, value}` | Setting changed or reset to default |

### `"scheduled_jobs"`

| Payload | Meaning |
|---|---|
| `:jobs_updated` | Any job run started or completed |

### `"session_lifecycle"`

| Payload | Meaning |
|---|---|
| `{:session_idle, session_id}` | Session transitioned to idle (completed or errored) |

---

## Subscribing in a LiveView

Always subscribe inside a `connected?(socket)` guard:

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    Events.subscribe_session(socket.assigns.session.id)
    Events.subscribe_agent_working()
  end

  {:ok, socket}
end
```

Handle messages in `handle_info/2`:

```elixir
def handle_info({:new_message, message}, socket) do
  {:noreply, update(socket, :messages, &[message | &1])}
end

def handle_info({:agent_working, _ref, _id}, socket) do
  {:noreply, assign(socket, :working, true)}
end
```

---

## Adding a new event

1. Add a named broadcast function to `Events`:

```elixir
@doc "Brief description of what triggered this."
def my_event(arg) do
  broadcast("my_topic", {:my_event, arg})
end
```

2. Add a matching subscribe helper if LiveViews need to receive it:

```elixir
@doc "Subscribe to my_topic events."
def subscribe_my_topic, do: sub("my_topic")
```

3. Update the topic table in this file and in the `@moduledoc`.

4. Write a test in `test/eye_in_the_sky_web/events_test.exs` following the existing pattern.

Do not hardcode the topic string in any caller — it lives in Events only.

---

## Known inconsistency

The `"agent:working"` topic has two payload shapes inherited from the migration:

- **Workers** (`WorkerEvents`, `SessionWorker`) broadcast `{:agent_working, session_ref, session_int_id}` — a string UUID and an integer ID.
- **REST API** (`SessionController`) broadcasts `{:agent_working, session}` — a session struct.

Subscribers must handle both. This will be normalized in a future pass.

---

## Compatibility shim

`EyeInTheSkyWebWeb.Helpers.PubSubHelpers` is a thin wrapper that delegates to Events. It exists for backwards compatibility with existing callers. Prefer calling Events directly in new code.
