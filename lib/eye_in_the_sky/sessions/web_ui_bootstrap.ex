defmodule EyeInTheSky.Sessions.WebUiBootstrap do
  @moduledoc false

  # Deterministic UUIDs for the web UI identity — stable across restarts.
  @web_agent_uuid "00000000-0000-0000-0000-000000000001"
  @web_session_uuid "00000000-0000-0000-0000-000000000002"

  @doc """
  Finds or creates the deterministic web UI session used by ChatLive.
  Returns the integer session ID.

  Safe to call on every mount — returns the existing session immediately
  if it was already bootstrapped.
  """
  @spec ensure_web_ui_session() :: integer()
  def ensure_web_ui_session do
    case EyeInTheSky.Sessions.get_session_by_uuid(@web_session_uuid) do
      {:ok, session} ->
        session.id

      {:error, :not_found} ->
        with {:ok, agent} <- find_or_create_web_agent(),
             {:ok, session} <-
               EyeInTheSky.Sessions.create_session(%{
                 uuid: @web_session_uuid,
                 agent_id: agent.id,
                 name: "Web UI",
                 started_at: DateTime.utc_now()
               }) do
          session.id
        else
          {:error, reason} ->
            raise "ensure_web_ui_session bootstrap failed: #{inspect(reason)}"
        end
    end
  end

  defp find_or_create_web_agent do
    case EyeInTheSky.Agents.get_agent_by_uuid(@web_agent_uuid) do
      {:ok, agent} ->
        {:ok, agent}

      {:error, :not_found} ->
        EyeInTheSky.Agents.create_agent(%{
          uuid: @web_agent_uuid,
          description: "Web UI User",
          source: "web"
        })
    end
  end
end
