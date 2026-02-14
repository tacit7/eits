defmodule EyeInTheSkyWeb.Sessions do
  @moduledoc """
  DEPRECATED: Backward compatibility wrapper for ExecutionAgents context.

  This module delegates all calls to ExecutionAgents. Use ExecutionAgents
  directly for new code. This wrapper exists only for backward compatibility
  and will be removed in a future phase.

  Migration: Session → ExecutionAgent (execution context)
             Agent → ChatAgent (chat identity)
  """

  alias EyeInTheSkyWeb.ExecutionAgents

  # Delegate all functions to ExecutionAgents context

  defdelegate list_sessions(opts \\ []), to: ExecutionAgents, as: :list_execution_agents
  defdelegate list_sessions_for_agent(agent_id, opts \\ []),
    to: ExecutionAgents,
    as: :list_execution_agents_for_chat_agent

  defdelegate get_session!(id), to: ExecutionAgents, as: :get_execution_agent!
  defdelegate get_session_by_uuid!(uuid), to: ExecutionAgents, as: :get_execution_agent_by_uuid!
  defdelegate get_session_by_uuid(uuid), to: ExecutionAgents, as: :get_execution_agent_by_uuid
  defdelegate get_session(id), to: ExecutionAgents, as: :get_execution_agent
  defdelegate get_session_with_logs!(id), to: ExecutionAgents, as: :get_execution_agent_with_logs!
  defdelegate create_session(attrs \\ %{}), to: ExecutionAgents, as: :create_execution_agent

  defdelegate create_session_with_model(attrs \\ %{}),
    to: ExecutionAgents,
    as: :create_execution_agent_with_model

  defdelegate update_session(session, attrs), to: ExecutionAgents, as: :update_execution_agent
  defdelegate end_session(session), to: ExecutionAgents, as: :end_execution_agent
  defdelegate archive_session(session), to: ExecutionAgents, as: :archive_execution_agent
  defdelegate unarchive_session(session), to: ExecutionAgents, as: :unarchive_execution_agent
  defdelegate delete_session(session), to: ExecutionAgents, as: :delete_execution_agent
  defdelegate change_session(session, attrs \\ %{}), to: ExecutionAgents, as: :change_execution_agent

  defdelegate list_active_sessions(opts \\ []),
    to: ExecutionAgents,
    as: :list_active_execution_agents

  defdelegate list_sessions_with_agent(opts \\ []),
    to: ExecutionAgents,
    as: :list_execution_agents_with_chat_agent

  defdelegate list_sessions_filtered(opts \\ []),
    to: ExecutionAgents,
    as: :list_execution_agents_filtered

  defdelegate list_session_overview_rows(opts \\ []),
    to: ExecutionAgents,
    as: :list_execution_agent_overview_rows

  defdelegate load_session_data(session_id), to: ExecutionAgents, as: :load_execution_agent_data
  defdelegate get_session_counts(session_id), to: ExecutionAgents, as: :get_execution_agent_counts
  defdelegate load_session_tasks(session_id), to: ExecutionAgents, as: :load_execution_agent_tasks

  defdelegate load_session_commits(session_id, opts \\ []),
    to: ExecutionAgents,
    as: :load_execution_agent_commits

  defdelegate load_session_logs(session_id, opts \\ []),
    to: ExecutionAgents,
    as: :load_execution_agent_logs

  defdelegate load_session_context(session_id),
    to: ExecutionAgents,
    as: :load_execution_agent_context

  defdelegate load_session_notes(session_id), to: ExecutionAgents, as: :load_execution_agent_notes
  defdelegate extract_model_info(model_data), to: ExecutionAgents
  defdelegate format_model_info(session), to: ExecutionAgents
end
