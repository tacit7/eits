defmodule EyeInTheSky.TaskOwnershipConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias EyeInTheSky.{Repo, Tasks}

  test "independent PostgreSQL transactions serialize competing claims and handoffs" do
    # Deliberately use independent connections: shared sandbox tasks cannot exercise
    # PostgreSQL row locking. Only these generated test-database fixtures are committed.
    {:ok, {task, session_ids, agent_id}} =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.transaction(fn ->
          now = DateTime.utc_now()

          {1, [agent]} =
            Repo.insert_all(
              EyeInTheSky.Agents.Agent,
              [%{uuid: Ecto.UUID.generate(), source: "test"}],
              returning: [:id]
            )

          {2, sessions} =
            Repo.insert_all(
              EyeInTheSky.Sessions.Session,
              Enum.map(1..2, fn _ ->
                %{
                  uuid: Ecto.UUID.generate(),
                  agent_id: agent.id,
                  status: "working",
                  started_at: now
                }
              end),
              returning: [:id]
            )

          {:ok, task} =
            Tasks.create_task(%{
              title: "Isolated ownership race #{Ecto.UUID.generate()}",
              state_id: 1
            })

          {task, Enum.map(sessions, & &1.id), agent.id}
        end)
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        parent = to_string(task.id)

        Repo.delete_all(
          from n in "notes", where: n.parent_type == "task" and n.parent_id == ^parent
        )

        Repo.delete_all(from ts in "task_sessions", where: ts.task_id == ^task.id)
        Repo.delete_all(from t in "tasks", where: t.id == ^task.id)
        Repo.delete_all(from s in "sessions", where: s.id in ^session_ids)
        Repo.delete_all(from a in "agents", where: a.id == ^agent_id)
      end)
    end)

    results = race(session_ids, fn id -> Tasks.claim_task(task, id) end)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :already_claimed})) == 1

    {owner_id, target_id} =
      Sandbox.unboxed_run(Repo, fn ->
        assert [owner_id] =
                 Repo.all(
                   from ts in "task_sessions",
                     where: ts.task_id == ^task.id,
                     select: ts.session_id
                 )

        target_id = Enum.find(session_ids, &(&1 != owner_id))
        # Both requests have identical input and run on independent connections;
        # one performs the transfer and the other observes its durable receipt.
        {owner_id, target_id}
      end)

    assert [{:ok, first}, {:ok, second}] =
             race([1, 2], fn _ -> Tasks.handoff_task(task, owner_id, target_id) end)

    assert first.updated_at == second.updated_at

    Sandbox.unboxed_run(Repo, fn ->
      assert [^target_id] =
               Repo.all(
                 from ts in "task_sessions", where: ts.task_id == ^task.id, select: ts.session_id
               )
    end)
  end

  defp race(values, fun) do
    parent = self()

    workers =
      Enum.map(values, fn value ->
        Elixir.Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            send(parent, {:ready, self()})

            receive do
              :go -> fun.(value)
            after
              5_000 -> raise "race start timed out"
            end
          end)
        end)
      end)

    Enum.each(workers, fn _ ->
      assert_receive {:ready, pid}, 5_000
      assert pid in Enum.map(workers, & &1.pid)
    end)

    Enum.each(workers, &send(&1.pid, :go))
    Enum.map(workers, &Elixir.Task.await(&1, 10_000))
  end
end
