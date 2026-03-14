defmodule EyeInTheSkyWeb.Factory do
  @moduledoc """
  Shared test factory helpers for controller and MCP tool tests.
  """

  alias EyeInTheSkyWeb.{Agents, Sessions}

  def uniq, do: System.unique_integer([:positive])

  def create_agent(overrides \\ %{}) do
    {:ok, agent} =
      Agents.create_agent(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            description: "Test agent #{uniq()}",
            source: "test"
          },
          overrides
        )
      )

    agent
  end

  def create_session(agent, overrides \\ %{}) do
    {:ok, session} =
      Sessions.create_session(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            agent_id: agent.id,
            name: "Test session #{uniq()}",
            status: "working",
            started_at: DateTime.utc_now() |> DateTime.to_iso8601()
          },
          overrides
        )
      )

    session
  end

  def new_session do
    agent = create_agent()
    create_session(agent)
  end

  def json_result({:reply, %Anubis.Server.Response{content: [%{"text" => json} | _]}, _frame}) do
    Jason.decode!(json, keys: :atoms)
  end
end
