defmodule EyeInTheSkyWeb.Teams.Subscriber do
  @moduledoc """
  Subscribes to session lifecycle PubSub events and drives team member state transitions.

  Decouples the Claude worker subsystem from the Teams context — workers broadcast
  session_idle events and this subscriber reacts by marking the corresponding
  team member as done.
  """

  use GenServer

  require Logger

  alias EyeInTheSkyWeb.{Events, Teams}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init([]) do
    Events.subscribe_session_lifecycle()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:session_idle, session_id}, state) do
    Teams.mark_member_done_by_session(session_id, "done")
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
