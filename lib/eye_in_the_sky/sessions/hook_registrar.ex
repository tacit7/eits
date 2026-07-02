defmodule EyeInTheSky.Sessions.HookRegistrar do
  @moduledoc false

  alias EyeInTheSky.Agents
  alias EyeInTheSky.Events
  alias EyeInTheSky.Sessions
  alias EyeInTheSky.Sessions.ModelInfo
  alias EyeInTheSky.Sessions.Session

  @spec register_from_hook(map(), integer() | nil) ::
          {:ok, %{session: Session.t(), agent: struct()}}
          | {:error, :agent | :session, Ecto.Changeset.t()}
  def register_from_hook(params, project_id) do
    session_uuid = params["session_id"]

    agent_attrs = %{
      uuid: params["agent_id"] || session_uuid,
      description: params["agent_description"] || params["description"],
      project_id: project_id,
      project_name: params["project_name"],
      git_worktree_path: params["worktree_path"],
      source: "hook"
    }

    case Agents.find_or_create_agent(agent_attrs) do
      {:ok, agent} ->
        {model_provider, model_name} = ModelInfo.parse_model_string(params["model"])

        session_attrs = %{
          uuid: session_uuid,
          agent_id: agent.id,
          name: params["name"],
          description: params["description"],
          status: "working",
          started_at: DateTime.utc_now(),
          provider: params["provider"] || "claude",
          model: params["model"],
          model_provider: model_provider,
          model_name: model_name,
          project_id: project_id,
          git_worktree_path: params["worktree_path"],
          entrypoint: params["entrypoint"],
          read_only: params["read_only"] == true or params["read_only"] == "true"
        }

        result =
          if model_name,
            do: Sessions.create_session_with_model(session_attrs),
            else: Sessions.create_session(session_attrs)

        case result do
          {:ok, session} ->
            Events.session_started(session)
            {:ok, %{session: session, agent: agent}}

          {:error, changeset} ->
            {:error, :session, changeset}
        end

      {:error, changeset} ->
        {:error, :agent, changeset}
    end
  end
end
