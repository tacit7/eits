defmodule EyeInTheSkyWeb.Assistants.ToolPolicy do
  @moduledoc """
  Single enforcement point for tool access and approval logic.

  All tool invocations from assistants must pass through `authorize/3`.
  Never scatter permission checks across workers or LiveViews.

  Flow:
    1. Tool must exist and be active in the catalog
    2. Assistant must have the tool in its allowed set (or open policy)
    3. If approval required — enqueue an approval record, return :requires_approval
    4. Otherwise — return :allowed
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.{Assistants, Repo}
  alias EyeInTheSkyWeb.Assistants.{Assistant, ToolApproval}

  @default_expiry_minutes 30

  @doc """
  Authorizes a tool invocation for an assistant session.

  Returns:
    - `{:ok, :allowed}` — tool may execute immediately
    - `{:ok, :requires_approval, approval}` — approval record created, execution blocked
    - `{:error, :tool_not_found}` — tool does not exist in the catalog
    - `{:error, :denied}` — assistant policy denies this tool
  """
  def authorize(session_id, assistant_id, tool_name, payload \\ %{}, opts \\ []) do
    with {:ok, _tool}      <- fetch_tool(tool_name),
         {:ok, assistant}  <- fetch_assistant(assistant_id),
         {:ok, decision}   <- Assistants.check_tool_policy(assistant, tool_name) do
      case decision do
        :allowed          -> {:ok, :allowed}
        :requires_approval -> enqueue_approval(session_id, assistant_id, tool_name, payload, opts)
      end
    end
  end

  @doc """
  Approves a pending tool approval. Returns the updated approval record.
  """
  def approve(approval_id, reviewed_by_id) do
    update_approval(approval_id, "approved", reviewed_by_id)
  end

  @doc """
  Denies a pending tool approval. Returns the updated approval record.
  """
  def deny(approval_id, reviewed_by_id) do
    update_approval(approval_id, "denied", reviewed_by_id)
  end

  @doc """
  Expires all pending approvals past their expires_at timestamp.
  Call from a scheduled job or on session end.
  """
  def expire_stale do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    {count, _} =
      ToolApproval
      |> where([a], a.status == "pending" and a.expires_at < ^now)
      |> Repo.update_all(set: [status: "expired", updated_at: now])

    {:ok, count}
  end

  @doc """
  Lists pending approvals, optionally scoped by session or assistant.
  """
  def list_pending(opts \\ []) do
    session_id   = Keyword.get(opts, :session_id)
    assistant_id = Keyword.get(opts, :assistant_id)

    ToolApproval
    |> where([a], a.status == "pending")
    |> then(fn q -> if session_id,   do: where(q, [a], a.session_id == ^session_id),   else: q end)
    |> then(fn q -> if assistant_id, do: where(q, [a], a.assistant_id == ^assistant_id), else: q end)
    |> order_by([a], asc: a.inserted_at)
    |> preload([:session, :assistant])
    |> Repo.all()
  end

  @doc """
  Lists all approvals with optional filters.
  """
  def list_approvals(opts \\ []) do
    session_id   = Keyword.get(opts, :session_id)
    assistant_id = Keyword.get(opts, :assistant_id)
    status       = Keyword.get(opts, :status)
    limit        = Keyword.get(opts, :limit, 50)

    ToolApproval
    |> then(fn q -> if session_id,   do: where(q, [a], a.session_id == ^session_id),     else: q end)
    |> then(fn q -> if assistant_id, do: where(q, [a], a.assistant_id == ^assistant_id), else: q end)
    |> then(fn q -> if status,       do: where(q, [a], a.status == ^status),             else: q end)
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> preload([:session, :assistant])
    |> Repo.all()
  end

  @doc """
  Gets a single approval by ID.
  """
  def get_approval!(id), do: Repo.get!(ToolApproval, id) |> Repo.preload([:session, :assistant])

  # ── Private ───────────────────────────────────────────────────────────────────

  defp fetch_tool(tool_name) do
    case Assistants.get_tool_by_name(tool_name) do
      nil  -> {:error, :tool_not_found}
      tool -> {:ok, tool}
    end
  end

  defp fetch_assistant(nil), do: {:ok, %Assistant{tool_policy: nil}}
  defp fetch_assistant(id) do
    case Assistants.get_assistant(id) do
      nil       -> {:ok, %Assistant{tool_policy: nil}}
      assistant -> {:ok, assistant}
    end
  end

  defp enqueue_approval(session_id, assistant_id, tool_name, payload, opts) do
    now     = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    minutes = Keyword.get(opts, :expiry_minutes, @default_expiry_minutes)
    expires = NaiveDateTime.add(now, minutes * 60, :second)

    attrs = %{
      session_id:        session_id,
      assistant_id:      assistant_id,
      tool_name:         tool_name,
      payload:           payload,
      status:            "pending",
      requested_by_type: Keyword.get(opts, :requested_by_type, "assistant"),
      requested_by_id:   Keyword.get(opts, :requested_by_id),
      expires_at:        expires,
      inserted_at:       now,
      updated_at:        now
    }

    case %ToolApproval{} |> ToolApproval.changeset(attrs) |> Repo.insert() do
      {:ok, approval} ->
        Phoenix.PubSub.broadcast(
          EyeInTheSkyWeb.PubSub,
          "tool_approvals",
          {:approval_requested, approval}
        )
        {:ok, :requires_approval, approval}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp update_approval(approval_id, status, reviewed_by_id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    approval = Repo.get!(ToolApproval, approval_id)

    approval
    |> ToolApproval.changeset(%{
      status:          status,
      reviewed_by_id:  reviewed_by_id,
      reviewed_at:     now,
      updated_at:      now
    })
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        Phoenix.PubSub.broadcast(
          EyeInTheSkyWeb.PubSub,
          "tool_approvals",
          {:approval_updated, updated}
        )
        {:ok, updated}

      err -> err
    end
  end
end
