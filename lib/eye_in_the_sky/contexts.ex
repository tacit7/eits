defmodule EyeInTheSky.Contexts do
  @moduledoc """
  The Contexts context for managing session and agent contexts.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Contexts.{AgentContext, SessionContext}
  alias EyeInTheSky.Repo

  # SessionContext functions

  @doc """
  Gets session context for a specific session.
  """
  def get_session_context(session_id) do
    case SessionContext
         |> where([sc], sc.session_id == ^session_id)
         |> order_by([sc], desc: sc.updated_at)
         |> limit(1)
         |> Repo.one() do
      nil -> {:error, :not_found}
      ctx -> {:ok, ctx}
    end
  end

  @doc """
  Creates or updates session context. Uses the unique index on session_id as the
  conflict target so concurrent writers cannot produce duplicates.
  """
  def upsert_session_context(attrs) do
    now = DateTime.utc_now()

    attrs_with_timestamps =
      attrs
      |> Map.put_new(:created_at, now)
      |> Map.put(:updated_at, now)

    %SessionContext{}
    |> SessionContext.changeset(attrs_with_timestamps)
    |> Repo.insert(
      on_conflict: {:replace, [:context, :metadata, :agent_id, :updated_at]},
      conflict_target: [:session_id],
      returning: true
    )
  end

  # AgentContext functions

  @doc """
  Gets agent context for a specific agent and project. Returns {:ok, context} | {:error, :not_found}.
  """
  def get_agent_context(agent_id, project_id) do
    case Repo.get_by(AgentContext, agent_id: agent_id, project_id: project_id) do
      nil -> {:error, :not_found}
      context -> {:ok, context}
    end
  end

  @doc """
  Creates or updates agent context. Uses the composite unique index on (agent_id, project_id)
  as the conflict target so concurrent writers cannot produce duplicates.
  """
  def upsert_agent_context(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs_with_timestamp = Map.put(attrs, :updated_at, now)

    %AgentContext{}
    |> AgentContext.changeset(attrs_with_timestamp)
    |> Repo.insert(
      on_conflict: {:replace, [:context, :updated_at]},
      conflict_target: [:agent_id, :project_id],
      returning: true
    )
  end
end
