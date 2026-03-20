defmodule EyeInTheSkyWebWeb.Api.V1.AgentController do
  use EyeInTheSkyWebWeb, :controller

  action_fallback EyeInTheSkyWebWeb.Api.V1.FallbackController

  import EyeInTheSkyWebWeb.ControllerHelpers

  alias EyeInTheSkyWeb.{Agents, Projects, Sessions, Teams}
  alias EyeInTheSkyWeb.Agents.AgentManager
  alias EyeInTheSkyWebWeb.Presenters.ApiPresenter

  require Logger

  alias EyeInTheSkyWebWeb.Helpers.ViewHelpers

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

  @doc """
  POST /api/v1/agents - Spawn a new Claude Code agent.
  Body: instructions, model, provider, project_path, project_id, name, member_name,
        parent_agent_id, parent_session_id, worktree, team_name
  """
  def create(conn, params) do
    with {:ok, params} <- validate_params(params),
         {:ok, project_id, project_name} <- Projects.resolve_project(params),
         {:ok, team} <- resolve_team(params) do
      params = Map.merge(params, %{"project_id" => project_id, "project_name" => project_name})
      instructions = apply_team_context(params["instructions"], team, params["member_name"])
      opts = build_spawn_opts(%{params | "instructions" => instructions}, team)

      case AgentManager.create_agent(opts) do
        {:ok, %{agent: agent, session: session}} ->
          maybe_join_team(team, agent, session, params["member_name"])

          conn
          |> put_status(:created)
          |> json(build_response(agent, session, team, params["member_name"]))

        {:error, :dirty_working_tree} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            error_code: "dirty_working_tree",
            message:
              "project_path has uncommitted changes; commit or stash before spawning a worktree agent"
          })

        {:error, reason} ->
          Logger.error("Agent spawn failed: #{inspect(reason)}")

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error_code: "spawn_failed", message: "Agent could not be started"})
      end
    else
      {:error, code, message} ->
        conn |> put_status(:bad_request) |> json(%{error_code: code, message: message})

      error ->
        Logger.error("Unexpected validation error in spawn: #{inspect(error)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error_code: "internal_error", message: "An unexpected error occurred"})
    end
  end

  defp maybe_join_team(nil, _agent, _session, _name), do: :ok

  defp maybe_join_team(team, agent, session, member_name) do
    result =
      Teams.join_team(%{
        team_id: team.id,
        agent_id: agent.id,
        session_id: session.id,
        name: member_name || agent.uuid,
        role: member_name || "agent",
        status: "active"
      })

    case result do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Team join failed: agent_id=#{agent.id} team_id=#{team.id} reason=#{inspect(reason)}"
        )

        :ok

      _ ->
        :ok
    end
  end

  defp build_team_context(team, member_name) do
    """
    ## Team Context
    You are member "#{member_name || "agent"}" of team "#{team.name}" (team_id: #{team.id}).
    You have been registered as a team member automatically.

    ## EITS Command Protocol

    How you issue EITS commands depends on your CLAUDE_CODE_ENTRYPOINT:

    **If CLAUDE_CODE_ENTRYPOINT=sdk-cli (headless/spawned agent):** emit EITS-CMD: lines in your output.
    The AgentWorker intercepts these in-process — no eits script, no HTTP calls needed.

      EITS-CMD: task begin <title>
      EITS-CMD: task annotate <task_id> <body>
      EITS-CMD: task done <task_id>
      EITS-CMD: dm --to <session_uuid> --message <msg>
      EITS-CMD: commit <hash>

    **If CLAUDE_CODE_ENTRYPOINT=cli (interactive session):** use the eits CLI script.

      eits tasks begin --title "Task name"
      eits tasks annotate <id> --body "What was done"
      eits tasks update <id> --state 4
      eits dm --to <session_uuid> --message "done"

    ## Task Completion
    When you finish a task, follow this sequence exactly:
    1. Annotate the task with a summary of what was done
    2. Mark it done (or move to in-review, state 4)
    3. DM the orchestrator session to report completion
    4. Run the `/i-update-status` slash command to commit work and update session tracking
    Do NOT skip any steps. The orchestrator needs to see what you did.
    """
  end

  defp coerce_parent_id(nil, _field), do: {:ok, nil}
  defp coerce_parent_id("", _field), do: {:ok, nil}
  defp coerce_parent_id(val, _field) when is_integer(val), do: {:ok, val}

  defp coerce_parent_id(val, field) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "invalid_parameter", "#{field} must be an integer"}
    end
  end

  defp coerce_parent_id(_val, field),
    do: {:error, "invalid_parameter", "#{field} must be an integer"}

  defp validate_instructions(nil),
    do: {:error, "missing_required", "instructions is required"}

  defp validate_instructions(val) when is_binary(val) do
    trimmed = String.trim(val)

    cond do
      trimmed == "" ->
        {:error, "missing_required", "instructions is required"}

      String.length(trimmed) > 32_000 ->
        {:error, "instructions_too_long", "instructions exceeds 32000 character limit"}

      true ->
        {:ok, trimmed}
    end
  end

  defp validate_provider_model(provider, model) do
    combos = ViewHelpers.valid_model_combos()

    case Map.get(combos, provider) do
      nil ->
        valid_providers = combos |> Map.keys() |> Enum.join(", ")

        {:error, "invalid_provider",
         "invalid provider '#{provider}'; must be one of: #{valid_providers}"}

      valid_models ->
        if model in valid_models do
          {:ok, {provider, model}}
        else
          {:error, "invalid_model",
           "invalid model '#{model}' for provider '#{provider}'; valid models: #{Enum.join(valid_models, ", ")}"}
        end
    end
  end

  defp validate_parent_agent(nil), do: {:ok, nil}

  defp validate_parent_agent(id) do
    case Agents.get_agent(id) do
      {:ok, _} -> {:ok, id}
      {:error, :not_found} -> {:error, "parent_not_found", "parent_agent_id #{id} does not exist"}
    end
  end

  defp validate_parent_session(nil), do: {:ok, nil}

  defp validate_parent_session(id) do
    case Sessions.get_session(id) do
      {:ok, _} ->
        {:ok, id}

      {:error, :not_found} ->
        {:error, "parent_not_found", "parent_session_id #{id} does not exist"}
    end
  end

  defp validate_params(params) do
    provider = params["provider"] || "claude"
    model = params["model"] || if(provider == "codex", do: "gpt-5.3-codex", else: "haiku")

    with {:ok, instructions} <- validate_instructions(params["instructions"]),
         {:ok, _} <- validate_provider_model(provider, model),
         {:ok, parent_agent_id} <- coerce_parent_id(params["parent_agent_id"], "parent_agent_id"),
         {:ok, parent_session_id} <-
           coerce_parent_id(params["parent_session_id"], "parent_session_id"),
         {:ok, _} <- validate_parent_agent(parent_agent_id),
         {:ok, _} <- validate_parent_session(parent_session_id) do
      {:ok,
       Map.merge(params, %{
         "instructions" => instructions,
         "provider" => provider,
         "model" => model,
         "parent_agent_id" => parent_agent_id,
         "parent_session_id" => parent_session_id
       })}
    end
  end

  defp resolve_team(params) do
    case params["team_name"] do
      name when name in [nil, ""] ->
        {:ok, nil}

      name ->
        case Teams.get_team_by_name(name) do
          nil -> {:error, "team_not_found", "team not found: #{name}"}
          team -> {:ok, team}
        end
    end
  end

  defp apply_team_context(instructions, nil, _member_name), do: instructions

  defp apply_team_context(instructions, team, member_name) do
    instructions <> "\n\n" <> build_team_context(team, member_name)
  end

  # Fix 2: accept name param, auto-generate from member_name+team or truncated instructions
  defp resolve_session_name(params, team) do
    name = params["name"]

    if name && String.trim(name) != "" do
      String.trim(name)
    else
      member_name = params["member_name"]
      team_name = team && team.name

      cond do
        member_name && team_name -> "#{member_name} @ #{team_name}"
        member_name -> member_name
        true -> String.slice(params["instructions"] || "Agent session", 0, 250)
      end
    end
  end

  defp build_spawn_opts(params, team) do
    name = resolve_session_name(params, team)

    [
      instructions: params["instructions"],
      model: params["model"],
      agent_type: params["provider"] || "claude",
      project_id: params["project_id"],
      project_name: params["project_name"],
      project_path: params["project_path"],
      name: name,
      description: name,
      worktree: params["worktree"],
      effort_level: params["effort_level"],
      parent_agent_id: params["parent_agent_id"],
      parent_session_id: params["parent_session_id"],
      agent: params["agent"],
      bypass_sandbox: params["bypass_sandbox"] == true
    ]
  end

  defp build_response(agent, session, nil, _member_name) do
    %{
      success: true,
      message: "Agent spawned",
      agent_id: agent.uuid,
      session_id: session.id,
      session_uuid: session.uuid
    }
  end

  defp build_response(agent, session, team, member_name) do
    %{
      success: true,
      message: "Agent spawned",
      agent_id: agent.uuid,
      session_id: session.id,
      session_uuid: session.uuid,
      team_id: team.id,
      team_name: team.name,
      member_name: member_name
    }
  end
end
