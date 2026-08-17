defmodule EyeInTheSkyWeb.Api.V1.ProjectScope do
  @moduledoc false

  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.{Agents, Projects, Sessions}

  def authorize_project_id(conn, params, raw_project_id) do
    with {:ok, project_id} <- normalize_project_id(raw_project_id) do
      if is_nil(project_id) do
        {:ok, nil}
      else
        with {:ok, scope} <- request_scope(conn, params),
             :ok <- validate_project_access(project_id, scope) do
          {:ok, project_id}
        end
      end
    end
  end

  def request_scope(conn, params) do
    session_id_raw = params["session_id"]
    agent_id_raw = params["agent_id"]
    header_session = conn |> Plug.Conn.get_req_header("x-eits-session") |> List.first()

    cond do
      session_id_raw && session_id_raw != "" ->
        Sessions.resolve(session_id_raw)

      agent_id_raw && agent_id_raw != "" ->
        resolve_agent_session(agent_id_raw)

      header_session && header_session != "" ->
        Sessions.resolve(header_session)

      true ->
        {:ok, :bearer_only}
    end
  end

  defp normalize_project_id(nil), do: {:ok, nil}
  defp normalize_project_id(""), do: {:ok, nil}
  defp normalize_project_id(raw) when is_integer(raw), do: {:ok, raw}

  defp normalize_project_id(raw) do
    case parse_int(raw) do
      nil -> {:error, :bad_request, "project_id must be an integer"}
      id -> {:ok, id}
    end
  end

  defp validate_project_access(_project_id, :bearer_only), do: :ok

  defp validate_project_access(project_id, %{project_id: nil}) do
    case Projects.get_project(project_id) do
      {:ok, _project} -> {:error, :forbidden, "Access denied"}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp validate_project_access(project_id, %{project_id: scope_project_id}) do
    with {:ok, project} <- Projects.get_project(project_id),
         {:ok, scope_project} <- Projects.get_project(scope_project_id) do
      if project.workspace_id == scope_project.workspace_id do
        :ok
      else
        {:error, :forbidden, "Access denied"}
      end
    else
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp resolve_agent_session(raw) do
    with {:ok, agent} <- resolve_agent(raw) do
      case Sessions.list_sessions_for_agent(agent.id) do
        [session | _] -> {:ok, session}
        [] -> {:error, :unauthorized}
      end
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp resolve_agent(raw) do
    if int_id = parse_int(raw) do
      Agents.get_agent(int_id)
    else
      Agents.get_agent_by_uuid(raw)
    end
  end
end
