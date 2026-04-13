defmodule EyeInTheSky.Contexts do
  @moduledoc """
  The Contexts context for managing session and agent contexts.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Contexts.{AgentContext, SessionContext}
  alias EyeInTheSky.QueryHelpers
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
  Creates or updates session context.
  """
  def upsert_session_context(attrs) do
    QueryHelpers.upsert(
      SessionContext,
      fn ->
        case get_session_context(attrs.session_id) do
          {:ok, ctx} -> ctx
          {:error, :not_found} -> nil
        end
      end,
      attrs
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
  Creates or updates agent context.
  """
  def upsert_agent_context(attrs) do
    QueryHelpers.upsert(
      AgentContext,
      fn ->
        case get_agent_context(attrs.agent_id, attrs.project_id) do
          {:ok, context} -> context
          {:error, :not_found} -> nil
        end
      end,
      attrs
    )
  end
end
