defmodule EyeInTheSkyWebWeb.Api.V1.AgentController do
  use EyeInTheSkyWebWeb, :controller

  action_fallback EyeInTheSkyWebWeb.Api.V1.FallbackController

  import EyeInTheSkyWebWeb.ControllerHelpers

  alias EyeInTheSkyWeb.{Agents, Claude.AgentManager, Teams}
  alias EyeInTheSkyWebWeb.Presenters.ApiPresenter

  @doc """
  GET /api/v1/agents - List agents.
  Query params: project_id, status, limit (default 20)
  """
  def index(conn, params) do
    limit = parse_int(params["limit"], 20)

    agents =
      if params["project_id"] do
        Agents.list_agents_by_project(parse_int(params["project_id"], nil)) |> Enum.take(limit)
      else
        Agents.list_agents() |> Enum.take(limit)
      end

    agents =
      if params["status"] do
        Enum.filter(agents, &(&1.status == params["status"]))
      else
        agents
      end

    json(conn, %{
      success: true,
      agents: Enum.map(agents, &ApiPresenter.present_agent/1)
    })
  end

  @doc """
  GET /api/v1/agents/:id - Get agent info.
  """
  def show(conn, %{"id" => id}) do
    result =
      case Integer.parse(id) do
        {int_id, ""} -> Agents.get_agent(int_id)
        _ -> Agents.get_agent_by_uuid(id)
      end

    with {:ok, agent} <- result do
      json(conn, %{success: true, agent: ApiPresenter.present_agent(agent)})
    end
  end

  @valid_models ~w(haiku sonnet opus)
  @max_instructions_length 32_000

  @doc """
  POST /api/v1/agents - Spawn a new Claude Code agent.
  Body: instructions, model, project_path, parent_agent_id, parent_session_id
  """
  def create(conn, params) do
    instructions = params["instructions"]
    model = params["model"] || "haiku"

    cond do
      is_nil(instructions) or instructions == "" ->
        conn |> put_status(:bad_request) |> json(%{error: "instructions is required"})

      String.length(instructions) > @max_instructions_length ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "instructions exceeds #{@max_instructions_length} character limit"})

      model not in @valid_models ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid model; must be one of: #{Enum.join(@valid_models, ", ")}"})

      true ->
        # Resolve team before spawning so we can inject team context into instructions
        team =
          case params["team_name"] do
            nil -> nil
            name -> Teams.get_team_by_name(name)
          end

        if params["team_name"] && is_nil(team) do
          conn
          |> put_status(:bad_request)
          |> json(%{error: "team not found: #{params["team_name"]}"})
        else
          instructions =
            case team do
              nil -> instructions
              t -> instructions <> "\n\n" <> build_team_context(t, params["member_name"])
            end

          opts = [
            instructions: instructions,
            model: model,
            agent_type: params["provider"] || "claude",
            project_id: parse_int(params["project_id"], nil),
            project_path: params["project_path"],
            description: String.slice(params["instructions"] || "Agent session", 0, 250),
            worktree: params["worktree"],
            effort_level: params["effort_level"],
            parent_agent_id: parse_int(params["parent_agent_id"], nil),
            parent_session_id: parse_int(params["parent_session_id"], nil),
            agent: params["agent"]
          ]

          case AgentManager.create_agent(opts) do
            {:ok, %{agent: agent, session: session}} ->
              maybe_join_team(team, agent, session, params["member_name"])

              base = %{
                success: true,
                message: "Agent spawned",
                agent_id: agent.uuid,
                session_id: session.id,
                session_uuid: session.uuid
              }

              result =
                if team do
                  Map.merge(base, %{
                    team_id: team.id,
                    team_name: team.name,
                    member_name: params["member_name"]
                  })
                else
                  base
                end

              conn |> put_status(:created) |> json(result)

            {:error, reason} ->
              require Logger
              Logger.error("Agent spawn failed: #{inspect(reason)}")

              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Spawn failed"})
          end
        end
    end
  end

  defp maybe_join_team(nil, _agent, _session, _name), do: :ok

  defp maybe_join_team(team, agent, session, member_name) do
    Teams.join_team(%{
      team_id: team.id,
      agent_id: agent.id,
      session_id: session.id,
      name: member_name || agent.uuid,
      role: member_name || "agent",
      status: "active"
    })
  end

  defp build_team_context(team, member_name) do
    """
    ## Team Context
    You are member "#{member_name || "agent"}" of team "#{team.name}" (team_id: #{team.id}).
    You have been registered as a team member automatically.
    Use i-team-members with team_id: #{team.id} to discover your teammates.
    Use i-todo list with team_id: #{team.id} to see shared tasks and claim work.
    Use i-team-join with command: "status" to update your status (active/idle/done).

    ## Task Completion
    When you finish a task or move it to in-review (state 4), follow this sequence exactly:
    1. Call `i-todo` with command: "annotate", task_id: "<task_id>", body: "Summary of what was done, decisions made, and any issues encountered"
    2. Call `i-todo` with command: "done", task_id: "<task_id>" (or command: "status", task_id: "<task_id>", state_id: 4 for in-review)
    3. Call `i-team-join` with command: "status", status: "done"
    4. Run the `/i-update-status` slash command to commit your work and update session tracking
    Do NOT skip any steps. The orchestrator needs to see what you did.
    """
  end
end
