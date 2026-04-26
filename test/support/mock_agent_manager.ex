defmodule EyeInTheSky.Agents.MockAgentManager do
  @moduledoc """
  Test double for AgentManager. Returns a configurable response instead of
  spawning real Claude processes.

  Configure per-test via Process.put:

      Process.put(:mock_agent_manager_response, {:ok, session})
      Process.put(:mock_agent_manager_response, {:error, :spawn_failed})

  Defaults to {:error, :spawn_failed} when no response is configured.
  """

  alias EyeInTheSky.Agents
  alias EyeInTheSky.Sessions

  def send_message(session_id, _message, _opts \\ []) do
    case Process.get(:mock_send_message_response, {:error, :no_worker}) do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      other -> other
    end
  rescue
    _ -> {:error, :mock_error}
  end

  def create_agent(_opts) do
    case Process.get(:mock_agent_manager_response, {:error, :spawn_failed}) do
      {:ok, :create_session} ->
        # Build a real agent + session for tests that need a successful spawn
        {:ok, agent} =
          Agents.create_agent(%{
            uuid: Ecto.UUID.generate(),
            description: "Mock agent",
            source: "test"
          })

        {:ok, session} =
          Sessions.create_session(%{
            uuid: Ecto.UUID.generate(),
            agent_id: agent.id,
            name: "Mock session",
            provider: "claude",
            started_at: DateTime.utc_now() |> DateTime.to_iso8601()
          })

        {:ok, %{agent: agent, session: session}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
