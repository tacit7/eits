defmodule EyeInTheSkyWebWeb.Helpers.PubSubHelpers do
  @moduledoc """
  Convenience wrappers for common Phoenix.PubSub subscriptions used across LiveViews.

  Call these inside `if connected?(socket) do` blocks in `mount/3`.
  """

  @pubsub EyeInTheSkyWeb.PubSub

  @doc "Subscribe to agent lifecycle events (created/updated/deleted)."
  def subscribe_agents do
    Phoenix.PubSub.subscribe(@pubsub, "agents")
  end

  @doc "Subscribe to agent working/stopped status events."
  def subscribe_agent_working do
    Phoenix.PubSub.subscribe(@pubsub, "agent:working")
  end

  @doc "Subscribe to task change events."
  def subscribe_tasks do
    Phoenix.PubSub.subscribe(@pubsub, "tasks")
  end

  @doc "Subscribe to session-specific events for the given session id."
  def subscribe_session(session_id) do
    Phoenix.PubSub.subscribe(@pubsub, "session:#{session_id}")
  end

  @doc "Subscribe to live-stream deltas for the given session id."
  def subscribe_dm_stream(session_id) do
    Phoenix.PubSub.subscribe(@pubsub, "dm:#{session_id}:stream")
  end

  @doc "Subscribe to the queued-prompt updates for the given session id."
  def subscribe_dm_queue(session_id) do
    Phoenix.PubSub.subscribe(@pubsub, "dm:#{session_id}:queue")
  end

  @doc "Subscribe to new messages broadcast on the given channel."
  def subscribe_channel_messages(channel_id) do
    Phoenix.PubSub.subscribe(@pubsub, "channel:#{channel_id}:messages")
  end
end
