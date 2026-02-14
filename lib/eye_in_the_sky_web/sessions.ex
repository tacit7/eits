defmodule EyeInTheSkyWeb.Sessions do
  @moduledoc """
  DEPRECATED: Backward compatibility wrapper for Agents context.

  This module delegates all calls to Agents. Use Agents
  directly for new code. This wrapper exists only for backward compatibility
  and will be removed in a future phase.

  Migration: Session → ExecutionAgent (execution context)
             Agent → ChatAgent (chat identity)
  """

  alias EyeInTheSkyWeb.Agents

  # Delegate all functions to Agents context

  defdelegate list_sessions(opts \\ []), to: Agents, as: :list_agents
  defdelegate list_sessions_for_agent(agent_id, opts \\ []),
    to: Agents,
    as: :list_agents_for_chat_agent

  defdelegate get_session!(id), to: Agents, as: :get_execution_agent!
  defdelegate get_session_by_uuid!(uuid), to: Agents, as: :get_execution_agent_by_uuid!
  defdelegate get_session_by_uuid(uuid), to: Agents, as: :get_execution_agent_by_uuid
  defdelegate get_session(id), to: Agents, as: :get_execution_agent
  defdelegate get_session_with_logs!(id), to: Agents, as: :get_execution_agent_with_logs!
  defdelegate create_session(attrs \\ %{}), to: Agents, as: :create_execution_agent

  defdelegate create_session_with_model(attrs \\ %{}),
    to: Agents,
    as: :create_execution_agent_with_model

  defdelegate update_session(session, attrs), to: Agents, as: :update_execution_agent
  defdelegate end_session(session), to: Agents, as: :end_execution_agent
  defdelegate archive_session(session), to: Agents, as: :archive_execution_agent
  defdelegate unarchive_session(session), to: Agents, as: :unarchive_execution_agent
  defdelegate delete_session(session), to: Agents, as: :delete_execution_agent
  defdelegate change_session(session, attrs \\ %{}), to: Agents, as: :change_execution_agent

  defdelegate list_active_sessions(opts \\ []),
    to: Agents,
    as: :list_active_agents

  defdelegate list_sessions_with_agent(opts \\ []),
    to: Agents,
    as: :list_agents_with_chat_agent

  defdelegate list_sessions_filtered(opts \\ []),
    to: Agents,
    as: :list_agents_filtered

  defdelegate list_session_overview_rows(opts \\ []),
    to: Agents,
    as: :list_execution_agent_overview_rows

  defdelegate load_session_data(session_id), to: Agents, as: :load_execution_agent_data
  defdelegate get_session_counts(session_id), to: Agents, as: :get_execution_agent_counts
  defdelegate load_session_tasks(session_id), to: Agents, as: :load_execution_agent_tasks

  defdelegate load_session_commits(session_id, opts \\ []),
    to: Agents,
    as: :load_execution_agent_commits

  defdelegate load_session_logs(session_id, opts \\ []),
    to: Agents,
    as: :load_execution_agent_logs

  defdelegate load_session_context(session_id),
    to: Agents,
    as: :load_execution_agent_context

  defdelegate load_session_notes(session_id), to: Agents, as: :load_execution_agent_notes
  defdelegate extract_model_info(model_data), to: Agents
  defdelegate format_model_info(session), to: Agents
end
