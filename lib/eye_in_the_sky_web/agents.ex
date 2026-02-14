defmodule EyeInTheSkyWeb.Agents do
  @moduledoc """
  DEPRECATED: Use EyeInTheSkyWeb.ChatAgents instead.

  This module is a backward compatibility wrapper that delegates to ChatAgents.
  The naming has been updated:
  - Agent (old) → ChatAgent (new) - represents chat identities/members
  - Session (old) → Agent (new, future) - represents execution contexts

  This wrapper will be removed in Phase 2 after all callers are updated.
  """

  alias EyeInTheSkyWeb.ChatAgents

  @doc "Deprecated: Use ChatAgents.list_chat_agents/0"
  defdelegate list_agents(), to: ChatAgents, as: :list_chat_agents

  @doc "Deprecated: Use ChatAgents.list_chat_agents_with_sessions/0"
  defdelegate list_agents_with_sessions(), to: ChatAgents, as: :list_chat_agents_with_sessions

  @doc "Deprecated: Use ChatAgents.list_active_chat_agents/0"
  defdelegate list_active_agents(), to: ChatAgents, as: :list_active_chat_agents

  @doc "Deprecated: Use ChatAgents.get_chat_agent_status_counts/1"
  defdelegate get_agent_status_counts(project_id \\ nil),
    to: ChatAgents,
    as: :get_chat_agent_status_counts

  @doc "Deprecated: Use ChatAgents.get_chat_agent!/1"
  defdelegate get_agent!(id), to: ChatAgents, as: :get_chat_agent!

  @doc "Deprecated: Use ChatAgents.get_chat_agent/1"
  defdelegate get_agent(id), to: ChatAgents, as: :get_chat_agent

  @doc "Deprecated: Use ChatAgents.get_chat_agent_with_associations!/1"
  defdelegate get_agent_with_associations!(id),
    to: ChatAgents,
    as: :get_chat_agent_with_associations!

  @doc "Deprecated: Use ChatAgents.populate_project_name/1"
  defdelegate populate_project_name(chat_agent), to: ChatAgents

  @doc "Deprecated: Use ChatAgents.create_chat_agent/1"
  defdelegate create_agent(attrs \\ %{}), to: ChatAgents, as: :create_chat_agent

  @doc "Deprecated: Use ChatAgents.update_chat_agent/2"
  defdelegate update_agent(chat_agent, attrs), to: ChatAgents, as: :update_chat_agent

  @doc "Deprecated: Use ChatAgents.update_chat_agent_status/2"
  defdelegate update_agent_status(chat_agent, status),
    to: ChatAgents,
    as: :update_chat_agent_status

  @doc "Deprecated: Use ChatAgents.delete_chat_agent/1"
  defdelegate delete_agent(chat_agent), to: ChatAgents, as: :delete_chat_agent

  @doc "Deprecated: Use ChatAgents.change_chat_agent/2"
  defdelegate change_agent(chat_agent, attrs \\ %{}), to: ChatAgents, as: :change_chat_agent

  @doc "Deprecated: Use ChatAgents.list_chat_agents_by_project/1"
  defdelegate list_agents_by_project(project_id),
    to: ChatAgents,
    as: :list_chat_agents_by_project

  @doc "Deprecated: Use ChatAgents.list_bookmarked_chat_agents/0"
  defdelegate list_bookmarked_agents(), to: ChatAgents, as: :list_bookmarked_chat_agents

  @doc "Deprecated: Use ChatAgents.get_chat_agent_by_uuid!/1"
  defdelegate get_agent_by_uuid!(uuid), to: ChatAgents, as: :get_chat_agent_by_uuid!

  @doc "Deprecated: Use ChatAgents.get_chat_agent_by_uuid/1"
  defdelegate get_agent_by_uuid(uuid), to: ChatAgents, as: :get_chat_agent_by_uuid

  @doc "Deprecated: Use ChatAgents.get_chat_agent_with_associations_by_uuid!/1"
  defdelegate get_agent_with_associations_by_uuid!(uuid),
    to: ChatAgents,
    as: :get_chat_agent_with_associations_by_uuid!

  @doc "Deprecated: Use ChatAgents.get_chat_agent_dashboard_data/1"
  defdelegate get_agent_dashboard_data(chat_agent_id),
    to: ChatAgents,
    as: :get_chat_agent_dashboard_data

  @doc "Deprecated: Use ChatAgents.get_chat_agent_dashboard_data_by_uuid/1"
  defdelegate get_agent_dashboard_data_by_uuid(uuid),
    to: ChatAgents,
    as: :get_chat_agent_dashboard_data_by_uuid
end
