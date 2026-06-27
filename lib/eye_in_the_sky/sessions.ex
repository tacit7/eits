defmodule EyeInTheSky.Sessions do
  @moduledoc """
  The Sessions context for managing autonomous execution units.

  A Session represents an autonomous Claude process doing work (execution context).
  """

  use EyeInTheSky.CrudHelpers, schema: EyeInTheSky.Sessions.Session

  import Ecto.Query, warn: false

  require Logger

  alias EyeInTheSky.Repo
  alias EyeInTheSky.Sessions.Loader
  alias EyeInTheSky.Sessions.ModelInfo
  alias EyeInTheSky.Sessions.Query
  alias EyeInTheSky.Sessions.Queries
  alias EyeInTheSky.Sessions.Session
  alias EyeInTheSky.Sessions.StatusTransitions
  alias EyeInTheSky.Settings.JsonSettings

  # --- Query Delegates ---
  defdelegate list_sessions(opts \\ []), to: Query
  defdelegate list_sessions_for_agent(agent_id, opts \\ []), to: Query
  defdelegate list_sessions_by_ids(ids), to: Query
  defdelegate list_sessions_by_mixed_ids(ids), to: Query
  defdelegate latest_session_id_by_agents(agent_ids), to: Query
  defdelegate list_idle_sessions_older_than(cutoff), to: Query
  defdelegate get_session!(id), to: Query
  defdelegate get_session_by_uuid!(uuid), to: Query
  defdelegate get_session_by_uuid(uuid), to: Query
  defdelegate get_session_id_by_uuid(uuid), to: Query
  defdelegate get_session(id), to: Query
  defdelegate get_session_with_agent(id), to: Query
  defdelegate agent_type_for_session(uuid), to: Query
  defdelegate resolve(ref), to: Query
  defdelegate list_active_sessions(opts \\ []), to: Query
  defdelegate list_active_sessions_for_project(project_id, opts \\ []), to: Query
  defdelegate list_sessions_with_agent(opts \\ []), to: Query
  defdelegate list_project_sessions_with_agent(project_id, opts \\ []), to: Query
  defdelegate count_and_ids_for_project(project_id), to: Query
  defdelegate list_sessions_for_scope(scope, opts \\ []), to: Query
  defdelegate preload_project(session), to: Query

  @doc """
  Creates a session.
  """
  @spec create_session(map()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def create_session(attrs \\ %{}), do: create(attrs)

  # --- Status Transition Delegates ---
  defdelegate set_session_idle(session), to: StatusTransitions
  defdelegate end_session(session, opts \\ %{}), to: StatusTransitions
  defdelegate archive_session(session), to: StatusTransitions
  defdelegate unarchive_session(session), to: StatusTransitions
  defdelegate delete_session(session), to: StatusTransitions
  defdelegate batch_delete_sessions(ids), to: StatusTransitions
  defdelegate batch_archive_sessions_for_project(ids, project_id), to: StatusTransitions

  @doc """
  Creates a session with model tracking information.

  Requires model_provider and model_name in attrs.
  Model info is immutable after creation.

  Returns {:ok, session} or {:error, changeset}.
  """
  def create_session_with_model(attrs \\ %{}) do
    %Session{}
    |> Session.creation_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a session, but prevents modification of model fields.

  Model information is immutable per session.
  Attempting to change model_provider or model_name will be ignored.
  """
  @spec update_session(Session.t(), map()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def update_session(%Session{} = session, attrs) do
    # Remove model fields if present - they are immutable
    attrs =
      attrs
      |> Map.delete(:model_provider)
      |> Map.delete(:model_name)
      |> Map.delete(:model_version)

    session
    |> Session.changeset(attrs)
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # JSONB settings overrides (sessions.settings)
  #
  # The session.settings column persists ONLY local overrides. Effective
  # settings are computed at read time via JsonSettings.effective_settings/2
  # (defaults ⊕ agent overrides ⊕ session overrides).
  # ---------------------------------------------------------------------------

  @doc """
  Read a single override via dotted key (no defaults applied). Returns nil
  when the key is absent — caller decides whether to fall back to agent or
  app defaults.
  """
  def get_setting(%Session{} = session, dotted_key) when is_binary(dotted_key) do
    JsonSettings.get_setting(session.settings || %{}, dotted_key)
  end

  @doc """
  Coerce + persist a single override on this session.
  Returns `{:ok, session}` or `{:error, reason}` (changeset or coerce error atom).
  """
  def put_setting(%Session{} = session, dotted_key, value) do
    case JsonSettings.coerce_value(value, dotted_key, :session) do
      {:ok, coerced} ->
        updated_settings = JsonSettings.put_setting(session.settings || %{}, dotted_key, coerced)
        persist_settings(session, updated_settings)

      {:error, _reason} = err ->
        err
    end
  end

  @doc """
  Remove a single override. Falls back to inherited value (agent or default).
  """
  def delete_setting(%Session{} = session, dotted_key) do
    updated_settings = JsonSettings.delete_setting(session.settings || %{}, dotted_key)
    persist_settings(session, updated_settings)
  end

  @doc "Drop an entire namespace of overrides (e.g. \"anthropic\")."
  def reset_settings_namespace(%Session{} = session, namespace) do
    updated_settings = JsonSettings.reset_namespace(session.settings || %{}, namespace)
    persist_settings(session, updated_settings)
  end

  @doc "Clear all overrides on this session."
  def reset_settings(%Session{} = session) do
    persist_settings(session, %{})
  end

  defp persist_settings(%Session{} = session, settings) when is_map(settings) do
    session
    |> Session.changeset(%{settings: settings})
    |> Repo.update()
  end


  @doc """
  Atomically increments the cached token and cost totals on a session row.

  Called after each message insert that carries usage metadata. Uses a raw
  SQL UPDATE so the increment is a single round-trip with no read-modify-write
  race. When `session_id` is nil or either delta is zero, this is a no-op.
  """
  @spec increment_usage_cache(integer() | nil, non_neg_integer(), float()) :: :ok
  def increment_usage_cache(nil, _tokens, _cost), do: :ok

  def increment_usage_cache(session_id, tokens, cost) do
    Repo.update_all(
      from(s in Session, where: s.id == ^session_id),
      inc: [total_tokens: tokens, total_cost_usd: cost]
    )

    :ok
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking session changes.
  """
  def change_session(%Session{} = session, attrs \\ %{}) do
    Session.changeset(session, attrs)
  end


  defdelegate list_sessions_filtered(opts \\ []), to: Queries
  defdelegate list_session_overview_rows(opts \\ []), to: Queries
  defdelegate get_session_overview_row(session_id), to: Queries
  defdelegate count_session_overview_rows(opts \\ []), to: Queries

  defdelegate load_session_data(session_id, opts \\ []), to: Loader
  defdelegate get_session_counts(session_id), to: Loader

  @doc """
  Returns statuses that indicate a session can no longer send or receive messages.
  """
  def terminated_statuses, do: ~w(completed failed)

  # --- Event Delegates ---
  defdelegate broadcast_session_updated(session), to: EyeInTheSky.Sessions.Events
  defdelegate broadcast_session_completed(session), to: EyeInTheSky.Sessions.Events
  defdelegate broadcast_session_waiting(session), to: EyeInTheSky.Sessions.Events
  defdelegate broadcast_status_side_effects(session, status), to: EyeInTheSky.Sessions.Events

  @doc """
  Extracts and validates model information from a nested model object.

  Delegates to ModelInfo.extract_model_info/1.
  """
  defdelegate extract_model_info(model_data), to: ModelInfo

  @doc """
  Gets model information for a session as a formatted string.

  Delegates to ModelInfo.format_model_info/1.
  Returns "provider/name (version)" or "provider/name" if version not set.
  """
  defdelegate format_model_info(session), to: ModelInfo

  defdelegate ensure_web_ui_session(), to: EyeInTheSky.Sessions.WebUiBootstrap

  defdelegate register_from_hook(params, project_id), to: EyeInTheSky.Sessions.HookRegistrar

  defdelegate record_tool_event(session, type, params),
    to: EyeInTheSky.Sessions.ToolEventRecorder

end
