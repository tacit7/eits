defmodule EyeInTheSkyWeb.Api.V1.AgentController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Agents, Sessions}
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  require Logger

  alias EyeInTheSkyWeb.Helpers.ViewHelpers

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
      if int_id = parse_int(id), do: Agents.get_agent(int_id), else: Agents.get_agent_by_uuid(id)

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
    with {:ok, params} <- validate_params(params) do
      case AgentManager.spawn_agent(params) do
        {:ok, %{agent: agent, session: session, team: team, member_name: member_name}} ->
          conn
          |> put_status(:created)
          |> json(build_response(agent, session, team, member_name))

        {:error, :dirty_working_tree} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            error_code: "dirty_working_tree",
            message:
              "project_path has uncommitted changes; commit or stash before spawning a worktree agent"
          })

        {:error, code, message} when is_binary(code) ->
          conn |> put_status(:bad_request) |> json(%{error_code: code, message: message})

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

  defp coerce_parent_id(nil, _field), do: {:ok, nil}
  defp coerce_parent_id("", _field), do: {:ok, nil}
  defp coerce_parent_id(val, _field) when is_integer(val), do: {:ok, val}

  defp coerce_parent_id(val, field) when is_binary(val) do
    case parse_int(val) do
      nil -> {:error, "invalid_parameter", "#{field} must be an integer"}
      int -> {:ok, int}
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

  defp build_response(agent, session, team, member_name) do
    base = %{
      success: true,
      message: "Agent spawned",
      agent_id: agent.uuid,
      session_id: session.id,
      session_uuid: session.uuid
    }

    if team do
      Map.merge(base, %{team_id: team.id, team_name: team.name, member_name: member_name})
    else
      base
    end
  end
end
