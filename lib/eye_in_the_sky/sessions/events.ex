defmodule EyeInTheSky.Sessions.Events do
  @moduledoc """
  PubSub event broadcasting for sessions.

  Delegates to BroadcastEvents for the actual broadcast implementations.
  """

  alias EyeInTheSky.Sessions.BroadcastEvents

  @doc "Broadcasts a session_updated event."
  defdelegate broadcast_session_updated(session), to: BroadcastEvents

  @doc "Broadcasts a session_completed event."
  defdelegate broadcast_session_completed(session), to: BroadcastEvents

  @doc "Broadcasts a session_waiting event."
  defdelegate broadcast_session_waiting(session), to: BroadcastEvents

  @doc "Broadcasts status-specific side effects for a session."
  defdelegate broadcast_status_side_effects(session, status), to: BroadcastEvents
end
