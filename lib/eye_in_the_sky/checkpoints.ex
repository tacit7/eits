defmodule EyeInTheSky.Checkpoints do
  @moduledoc """
  Context for session checkpointing: save, restore, and fork session state.
  """

  import Ecto.Query, warn: false
  require Logger

  alias EyeInTheSky.{Agents, Messages, Sessions}
  alias EyeInTheSky.Checkpoints.Checkpoint
  alias EyeInTheSky.Repo

  @doc """
  Lists all checkpoints for a session, ordered oldest first.
  """
  def list_checkpoints_for_session(session_id) do
    Checkpoint
    |> where([c], c.session_id == ^session_id)
    |> order_by([c], asc: c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates a checkpoint for the given session.

  Captures the current message count as message_index.
  If a project_path is provided, attempts a `git stash` in that directory
  and stores the resulting stash ref.

  Returns `{:ok, checkpoint}` or `{:error, reason}`.
  """
  def create_checkpoint(session_id, attrs \\ %{}) do
    message_index = Messages.count_messages_for_session(session_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    project_path = Map.get(attrs, :project_path)

    git_stash_ref =
      if project_path && File.dir?(project_path) do
        stash_session_state(project_path)
      else
        nil
      end

    params = %{
      session_id: session_id,
      name: Map.get(attrs, :name, "Checkpoint #{message_index}"),
      description: Map.get(attrs, :description),
      message_index: message_index,
      git_stash_ref: git_stash_ref,
      metadata: Map.get(attrs, :metadata, %{}),
      inserted_at: now
    }

    %Checkpoint{}
    |> Checkpoint.changeset(params)
    |> Repo.insert()
  end

  @doc """
  Restores a session to a checkpoint by deleting messages created after
  checkpoint.message_index (keeping the N oldest).

  If the checkpoint has a git_stash_ref, attempts to restore that stash
  in the session's project directory.

  Returns `{:ok, deleted_count}` or `{:error, reason}`.
  """
  def restore_checkpoint(%Checkpoint{} = checkpoint) do
    deleted =
      Messages.truncate_messages_after_index(checkpoint.session_id, checkpoint.message_index)

    if checkpoint.git_stash_ref do
      session = case Sessions.get_session(checkpoint.session_id) do
        {:ok, s} -> s
        {:error, :not_found} -> nil
      end

      project_path = session && session.git_worktree_path

      if project_path && File.dir?(project_path) do
        pop_stash(project_path, checkpoint.git_stash_ref)
      end
    end

    {:ok, deleted}
  end

  @doc """
  Forks a session from a checkpoint.

  Creates a new session record (child of the original), copies messages
  0..message_index into it, and optionally creates a new git branch
  from the stash ref.

  Returns `{:ok, new_session}` or `{:error, reason}`.
  """
  def fork_checkpoint(%Checkpoint{} = checkpoint, attrs \\ %{}) do
    with {:ok, session} <- Sessions.get_session(checkpoint.session_id),
         {:ok, agent} <- get_or_create_fork_agent(session, attrs),
         {:ok, new_session} <- create_fork_session(session, agent, checkpoint, attrs),
         :ok <- copy_messages_to_fork(checkpoint.session_id, new_session.id, checkpoint.message_index) do
      maybe_create_fork_branch(checkpoint, session, new_session, attrs)
      {:ok, new_session}
    end
  end

  @doc """
  Gets a checkpoint by ID.
  """
  def get_checkpoint(id) do
    case Repo.get(Checkpoint, id) do
      nil -> {:error, :not_found}
      checkpoint -> {:ok, checkpoint}
    end
  end

  @doc """
  Deletes a checkpoint.
  """
  def delete_checkpoint(%Checkpoint{} = checkpoint) do
    Repo.delete(checkpoint)
  end

  # Private

  defp maybe_create_fork_branch(checkpoint, original_session, new_session, attrs) do
    if checkpoint.git_stash_ref && original_session.git_worktree_path &&
         File.dir?(original_session.git_worktree_path) do
      branch_name = attrs[:branch_name] || "fork/session-#{new_session.id}"
      create_branch_from_stash(original_session.git_worktree_path, checkpoint.git_stash_ref, branch_name)
    end
  end

  defp stash_session_state(project_path) do
    stash_message = "eits-checkpoint-#{System.system_time(:millisecond)}"

    case System.cmd("git", ["-C", project_path, "stash", "push", "-m", stash_message],
           stderr_to_stdout: false
         ) do
      {output, 0} ->
        case Regex.run(~r/stash@\{(\d+)\}/, output) do
          [_, n] -> resolve_stash_ref(project_path, n)
          _ -> nil
        end

      {reason, code} ->
        Logger.warning("git stash failed (exit #{code}): #{String.trim(reason)}")
        nil
    end
  end

  defp resolve_stash_ref(project_path, n) do
    case System.cmd("git", ["-C", project_path, "rev-parse", "stash@{#{n}}"],
           stderr_to_stdout: false
         ) do
      {hash, 0} -> String.trim(hash)
      _ -> "stash@{#{n}}"
    end
  end

  defp pop_stash(project_path, stash_ref) do
    {_output, code} =
      System.cmd("git", ["-C", project_path, "stash", "apply", stash_ref],
        stderr_to_stdout: false
      )

    if code != 0 do
      Logger.warning("git stash apply #{stash_ref} failed with exit #{code}")
    end
  end

  defp create_branch_from_stash(project_path, stash_ref, branch_name) do
    {_output, code} =
      System.cmd(
        "git",
        ["-C", project_path, "stash", "branch", branch_name, stash_ref],
        stderr_to_stdout: false
      )

    if code != 0 do
      Logger.warning("git stash branch #{branch_name} from #{stash_ref} failed")
    end
  end

  defp get_or_create_fork_agent(original_session, attrs) do
    description = attrs[:agent_description] || "Fork of session #{original_session.id}"

    case Agents.create_agent(%{
           uuid: Ecto.UUID.generate(),
           description: description,
           source: "fork",
           parent_agent_id: original_session.agent_id,
           project_id: original_session.project_id
         }) do
      {:ok, agent} -> {:ok, agent}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp create_fork_session(original_session, agent, checkpoint, attrs) do
    name =
      attrs[:session_name] || "Fork: #{original_session.name || "session #{original_session.id}"}"

    Sessions.create_session(%{
      uuid: Ecto.UUID.generate(),
      agent_id: agent.id,
      name: name,
      description: "Forked from session #{original_session.id} at checkpoint #{checkpoint.id}",
      status: "idle",
      provider: original_session.provider || "claude",
      model: original_session.model,
      project_id: original_session.project_id,
      git_worktree_path: original_session.git_worktree_path,
      parent_session_id: original_session.id,
      started_at: DateTime.utc_now()
    })
  end

  defp copy_messages_to_fork(source_session_id, dest_session_id, message_index) do
    messages_to_copy =
      Messages.list_recent_messages(source_session_id, message_index)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.each(messages_to_copy, fn msg ->
      Messages.create_message(%{
        uuid: Ecto.UUID.generate(),
        session_id: dest_session_id,
        sender_role: msg.sender_role,
        recipient_role: msg.recipient_role,
        direction: msg.direction || "inbound",
        body: msg.body,
        status: "delivered",
        provider: msg.provider || "claude",
        metadata: msg.metadata || %{},
        inserted_at: msg.inserted_at || now,
        updated_at: now
      })
    end)

    :ok
  end
end
