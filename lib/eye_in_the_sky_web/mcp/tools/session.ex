defmodule EyeInTheSkyWeb.MCP.Tools.Session do
  @moduledoc "Session management. Commands: start, update, info, search, save-context, load-context"

  use Anubis.Server.Component, type: :tool

  alias EyeInTheSkyWeb.MCP.Tools.{Helpers, ResponseHelper}
  alias EyeInTheSkyWeb.Sessions

  schema do
    field :command, :string, required: true, description: "Command to execute"
    field :session_id, :string, description: "Claude Code session ID (mandatory for start)"
    field :name, :string, description: "Human-readable session name"
    field :description, :string, description: "What you'll be working on (for start)"
    field :agent_id, :string, description: "Agent UUID identifier"

    field :agent_description, :string,
      description: "Agent name/label (e.g., 'Frontend Dev Agent')"

    field :project_name, :string, description: "Project name"
    field :worktree_path, :string, description: "Path to git repository"
    field :model, :string, description: "Model identifier (e.g., claude-sonnet-4-5-20250929)"
    field :provider, :string, description: "AI provider name (default: 'claude')"
    field :parent_agent_id, :string, description: "Parent agent ID if this is a subagent"
    field :parent_session_id, :string, description: "Parent session ID if this is a subsession"
    field :persona_id, :string, description: "Persona ID to load initial context from"
    field :status, :string, description: "Session status (for update)"
    field :summary, :string, description: "Summary of work completed (for end)"

    field :final_status, :string,
      description: "Either 'completed' or 'failed' (for end, defaults to 'completed')"

    field :query, :string, description: "Search query (for search)"
    field :context, :string, description: "Markdown formatted context (for save-context)"
    field :limit, :integer, description: "Maximum results (default: 20)"
  end

  @impl true
  def execute(%{command: "start"} = params, frame) do
    attrs = %{
      uuid: params[:session_id],
      name: params[:name],
      description: params[:description],
      project_name: params[:project_name],
      worktree_path: params[:worktree_path],
      status: "working"
    }

    agent_attrs = %{
      uuid: params[:agent_id] || params[:session_id],
      description: params[:agent_description] || params[:description],
      status: "working",
      model: params[:model],
      provider: params[:provider] || "claude"
    }

    result = create_or_find_session(attrs, agent_attrs)
    response = ResponseHelper.json_response(result)
    # Store EITS session UUID in frame assigns so other tools (e.g. i-todo) can
    # auto-link to this session without requiring an explicit session_id param.
    updated_frame =
      if params[:session_id] && is_struct(frame) do
        Anubis.Server.Frame.assign(frame, :eits_session_id, params[:session_id])
      else
        frame
      end

    {:reply, response, updated_frame}
  end

  def execute(%{command: "end"} = params, frame) do
    result = end_session(params)
    response = ResponseHelper.json_response(result)
    {:reply, response, frame}
  end

  def execute(%{command: "update"} = params, frame) do
    result = update_session(params)
    response = ResponseHelper.json_response(result)
    {:reply, response, frame}
  end

  def execute(%{command: "info"} = params, frame) do
    result = get_session_info(params)
    response = ResponseHelper.json_response(result)
    {:reply, response, frame}
  end

  def execute(%{command: "search"} = params, frame) do
    result = search_sessions(params)
    response = ResponseHelper.json_response(result)
    {:reply, response, frame}
  end

  def execute(%{command: "save-context"} = params, frame) do
    result = save_context(params)
    response = ResponseHelper.json_response(result)
    {:reply, response, frame}
  end

  def execute(%{command: "load-context"} = params, frame) do
    result = load_context(params)
    response = ResponseHelper.json_response(result)
    {:reply, response, frame}
  end

  def execute(%{command: cmd}, frame) do
    response = ResponseHelper.error_response("Unknown command: #{cmd}")
    {:reply, response, frame}
  end

  # Private helpers

  defp create_or_find_session(attrs, agent_attrs) do
    alias EyeInTheSkyWeb.Agents
    alias EyeInTheSkyWeb.Projects

    session_uuid = attrs[:uuid]

    project_id =
      case attrs[:project_name] do
        nil ->
          nil

        name ->
          case Projects.get_project_by_name(name) do
            nil -> nil
            project -> project.id
          end
      end

    session_result =
      case Sessions.get_session_by_uuid(session_uuid) do
        {:ok, session} ->
          update_attrs =
            %{}
            |> Helpers.maybe_put(:name, attrs[:name])
            |> Helpers.maybe_put(:description, agent_attrs[:description])
            |> Helpers.maybe_put(:project_id, project_id)

          case Sessions.update_session(session, update_attrs) do
            {:ok, updated} -> {:ok, updated}
            {:error, _} -> {:ok, session}
          end

        {:error, :not_found} ->
          agent =
            case Agents.list_active_agents() |> List.first() do
              nil ->
                case Agents.create_agent(%{name: "default", status: "working"}) do
                  {:ok, a} -> a
                  {:error, _} -> nil
                end

              a ->
                a
            end

          if is_nil(agent) do
            {:error, %{errors: [agent: {"could not create default agent", []}]}}
          else
            Sessions.create_session(%{
              uuid: session_uuid,
              name: attrs[:name],
              description: agent_attrs[:description],
              status: agent_attrs[:status] || "working",
              agent_id: agent.id,
              project_id: project_id,
              started_at: DateTime.utc_now() |> DateTime.to_iso8601()
            })
          end
      end

    case session_result do
      {:ok, session} ->
        %{
          success: true,
          message: "Session #{attrs[:uuid]} ready",
          session_id: attrs[:uuid],
          agent_id: session.agent_id,
          session_int_id: session.id
        }

      {:error, changeset} ->
        %{success: false, message: "Failed to create session: #{inspect(changeset.errors)}"}
    end
  end

  defp end_session(params) do
    opts =
      %{}
      |> then(fn m ->
        if params[:summary], do: Map.put(m, :summary, params[:summary]), else: m
      end)
      |> then(fn m ->
        if params[:final_status], do: Map.put(m, :final_status, params[:final_status]), else: m
      end)

    case Sessions.get_session_by_uuid(params[:agent_id] || params[:session_id]) do
      {:ok, session} ->
        case Sessions.end_session(session, opts) do
          {:ok, _} ->
            %{success: true, message: "Session ended"}

          {:error, changeset} ->
            %{success: false, message: "Failed to end session: #{inspect(changeset.errors)}"}
        end

      {:error, :not_found} ->
        %{success: false, message: "Session not found"}
    end
  end

  defp update_session(params) do
    uuid = params[:session_id] || params[:agent_id]

    case Sessions.get_session_by_uuid(uuid) do
      {:ok, session} ->
        update_attrs =
          %{}
          |> Helpers.maybe_put(:name, params[:name])
          |> Helpers.maybe_put(:status, params[:status])
          |> Helpers.maybe_put(:description, params[:description])

        case Sessions.update_session(session, update_attrs) do
          {:ok, _} -> %{success: true, message: "Session updated"}
          {:error, cs} -> %{success: false, message: "Update failed: #{inspect(cs.errors)}"}
        end

      {:error, :not_found} ->
        %{success: false, message: "Session not found: #{uuid}"}
    end
  end

  defp get_session_info(params) do
    uuid = params[:session_id] || params[:agent_id]

    if uuid do
      case Sessions.get_session_by_uuid(uuid) do
        {:ok, session} ->
          %{
            success: true,
            agent_id: session.agent_id,
            session_id: uuid,
            status: session.status,
            initialized: true
          }

        {:error, :not_found} ->
          %{success: false, message: "Session not found", initialized: false}
      end
    else
      %{success: false, message: "session_id or agent_id required", initialized: false}
    end
  end

  defp search_sessions(params) do
    query = params[:query] || ""
    results = Sessions.list_sessions_filtered(search_query: query)

    %{
      success: true,
      message: "Found #{length(results)} session(s)",
      results:
        Enum.map(results, fn s ->
          %{id: s.id, uuid: s.uuid, description: s.description, status: s.status}
        end)
    }
  end

  defp save_context(params) do
    alias EyeInTheSkyWeb.Contexts

    case Sessions.get_session_by_uuid(params[:session_id]) do
      {:ok, session} ->
        case Contexts.upsert_session_context(%{
               session_id: session.id,
               agent_id: session.agent_id,
               context: params[:context]
             }) do
          {:ok, _} -> %{success: true, message: "Context saved"}
          {:error, cs} -> %{success: false, message: "Save failed: #{inspect(cs.errors)}"}
        end

      {:error, :not_found} ->
        %{success: false, message: "Session not found: #{params[:session_id]}"}
    end
  end

  defp load_context(params) do
    alias EyeInTheSkyWeb.Contexts

    case Helpers.resolve_session_int_id(params[:session_id]) do
      {:error, _} ->
        %{success: false, message: "Session not found: #{params[:session_id]}"}

      {:ok, int_id} ->
        case Contexts.get_session_context(int_id) do
          nil ->
            %{success: false, message: "No context found"}

          ctx ->
            %{
              success: true,
              message: "Context loaded",
              context: ctx.context,
              created_at: ctx.created_at,
              updated_at: ctx.updated_at
            }
        end
    end
  end

end
