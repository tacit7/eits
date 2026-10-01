defmodule EyeInTheSky.TaskOwnershipLifecycleTest do
  use EyeInTheSky.DataCase, async: false
  import EyeInTheSky.Factory
  alias EyeInTheSky.Tasks

  setup do
    owner = create_session(create_agent())
    target = create_session(create_agent())
    stranger = create_session(create_agent())
    {:ok, task} = Tasks.create_task(%{title: "Ownership lifecycle", state_id: 1})
    %{task: task, owner: owner, target: target, stranger: stranger}
  end

  defp owners(task) do
    Repo.all(from ts in "task_sessions", where: ts.task_id == ^task.id, select: ts.session_id)
  end

  test "claim retry succeeds only for its owner, even with stale task input", c do
    assert {:ok, first} = Tasks.claim_task(c.task, c.owner.id)
    assert {:ok, retry} = Tasks.claim_task(c.task, c.owner.id)
    assert retry.updated_at == first.updated_at
    assert {:error, :already_claimed} = Tasks.claim_task(c.task, c.stranger.id)
    assert owners(c.task) == [c.owner.id]
  end

  test "release is atomic, owner-only, and safely retryable", c do
    assert {:ok, _} = Tasks.claim_task(c.task, c.owner.id)
    assert {:error, :not_owner} = Tasks.release_task(c.task, c.stranger.id)
    assert {:ok, released} = Tasks.release_task(c.task, c.owner.id)
    assert released.state_id == 1
    assert owners(c.task) == []
    assert {:ok, retry} = Tasks.release_task(c.task, c.owner.id)
    assert retry.updated_at == released.updated_at
    assert {:error, :not_owner} = Tasks.release_task(c.task, c.stranger.id)
    assert {:ok, _} = Tasks.claim_task(c.task, c.target.id)
    assert {:error, :not_owner} = Tasks.release_task(c.task, c.owner.id)
    assert owners(c.task) == [c.target.id]
  end

  test "handoff transfers a single owner and retries cannot steal subsequent work", c do
    assert {:ok, _} = Tasks.claim_task(c.task, c.owner.id)
    assert {:error, :not_owner} = Tasks.handoff_task(c.task, c.stranger.id, c.target.id)
    assert {:ok, handed} = Tasks.handoff_task(c.task, c.owner.id, c.target.id)
    assert handed.state_id == 2
    assert owners(c.task) == [c.target.id]
    assert {:ok, retry} = Tasks.handoff_task(c.task, c.owner.id, c.target.id)
    assert retry.updated_at == handed.updated_at
    assert {:error, :not_owner} = Tasks.handoff_task(c.task, c.stranger.id, c.target.id)
    assert {:ok, _} = Tasks.handoff_task(c.task, c.target.id, c.stranger.id)
    assert {:error, :not_owner} = Tasks.handoff_task(c.task, c.owner.id, c.target.id)
    assert owners(c.task) == [c.stranger.id]
  end

  test "handoff preserves In Review, clears target intent, and records only one receipt", c do
    assert {:ok, claimed} = Tasks.claim_task(c.task, c.owner.id)
    assert {:ok, _} = Tasks.update_task_state(claimed, 4)

    Repo.update_all(from(s in EyeInTheSky.Sessions.Session, where: s.id == ^c.target.id),
      set: [intent: "done", intent_set_at: DateTime.utc_now()]
    )

    assert {:ok, handed} = Tasks.handoff_task(c.task, c.owner.id, c.target.id)
    assert handed.state_id == 4
    assert {:ok, _} = Tasks.handoff_task(c.task, c.owner.id, c.target.id)
    target = Repo.get!(EyeInTheSky.Sessions.Session, c.target.id)
    assert target.intent == nil
    assert target.intent_set_at == nil
    parent_id = to_string(c.task.id)

    assert Repo.aggregate(
             from(n in EyeInTheSky.Notes.Note,
               where: n.parent_type == "task" and n.parent_id == ^parent_id
             ),
             :count
           ) == 1

    assert {:ok, released} = Tasks.release_task(c.task, c.target.id)
    assert released.state_id == 1
  end

  test "handoff to self is a no-op and archived tasks stay untouched", c do
    assert {:ok, claimed} = Tasks.claim_task(c.task, c.owner.id)
    assert {:ok, same} = Tasks.handoff_task(c.task, c.owner.id, c.owner.id)
    assert same.updated_at == claimed.updated_at
    assert {:ok, _} = Tasks.archive_task(claimed)
    assert {:error, :task_not_claimable} = Tasks.claim_task(c.task, c.owner.id)
    assert {:error, :task_not_active} = Tasks.release_task(c.task, c.owner.id)
    assert {:error, :task_not_active} = Tasks.handoff_task(c.task, c.owner.id, c.target.id)
    assert owners(c.task) == [c.owner.id]
  end

  test "invalid target leaves state and ownership intact", c do
    assert {:ok, first} = Tasks.claim_task(c.task, c.owner.id)
    assert {:error, :invalid_session} = Tasks.handoff_task(c.task, c.owner.id, -1)
    assert owners(c.task) == [c.owner.id]
    assert {:ok, current} = Tasks.get_task(c.task.id)
    assert current.updated_at == first.updated_at
  end

  test "completed tasks retain state and ownership", c do
    assert {:ok, claimed} = Tasks.claim_task(c.task, c.owner.id)
    assert {:ok, %{task: completed}} = Tasks.complete_task(claimed, "Finished")
    assert {:error, :task_not_claimable} = Tasks.claim_task(c.task, c.owner.id)
    assert {:error, :task_not_active} = Tasks.release_task(c.task, c.owner.id)
    assert {:error, :task_not_active} = Tasks.handoff_task(c.task, c.owner.id, c.target.id)
    assert {:ok, current} = Tasks.get_task(c.task.id)
    assert current.state_id == 3
    assert current.completed_at == completed.completed_at
    assert owners(c.task) == [c.owner.id]
  end
end
