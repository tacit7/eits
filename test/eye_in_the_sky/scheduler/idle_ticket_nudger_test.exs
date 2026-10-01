defmodule EyeInTheSky.Scheduler.IdleTicketNudgerTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.Agents
  alias EyeInTheSky.Messages
  alias EyeInTheSky.Scheduler.IdleTicketNudger
  alias EyeInTheSky.Sessions
  alias EyeInTheSky.Tasks

  defp create_agent(overrides \\ %{}) do
    {:ok, agent} =
      Agents.create_agent(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            description: "Idle ticket nudger test agent",
            source: "test"
          },
          overrides
        )
      )

    agent
  end

  defp create_session(overrides \\ %{}) do
    stale = DateTime.utc_now() |> DateTime.add(-10 * 60, :second)

    {:ok, session} =
      Sessions.create_session(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            agent_id: create_agent().id,
            name: "Idle ticket nudger test session",
            status: "idle",
            started_at: stale,
            last_activity_at: stale,
            provider: "claude"
          },
          overrides
        )
      )

    session
  end

  defp create_task(overrides \\ %{}) do
    {:ok, task} =
      Tasks.create_task(
        Map.merge(
          %{
            title: "Update implementation ticket",
            state_id: Tasks.state_in_progress(),
            priority: 0
          },
          overrides
        )
      )

    task
  end

  defp wait_for_codex_port(worker, attempts \\ 40)
  defp wait_for_codex_port(_worker, 0), do: nil

  defp wait_for_codex_port(worker, attempts) do
    ref = :sys.get_state(worker).sdk_ref
    port = if ref, do: EyeInTheSky.Claude.SDK.Registry.lookup(ref)

    if is_pid(port) do
      port
    else
      Process.sleep(25)
      wait_for_codex_port(worker, attempts - 1)
    end
  end

  describe "run_once_for_testing/1" do
    test "scheduler wakes an absent Codex worker and records its response" do
      previous_manager = Application.get_env(:eye_in_the_sky, :agent_manager_module)

      Application.put_env(
        :eye_in_the_sky,
        :agent_manager_module,
        EyeInTheSky.Agents.AgentManager
      )

      session =
        create_session(%{
          provider: "codex",
          entrypoint: "sdk-cli",
          managed_by_app: true,
          git_worktree_path: File.cwd!()
        })

      try do
        task = create_task()
        Tasks.link_session_to_task(task.id, session.id)
        Phoenix.PubSub.subscribe(EyeInTheSky.PubSub, "session:#{session.id}")
        assert Registry.lookup(EyeInTheSky.Claude.AgentRegistry, {:session, session.id}) == []

        {_state, stats} = IdleTicketNudger.run_once_for_testing(idle_age_seconds: 60)
        assert stats.sent == 1

        [{worker, "codex"}] =
          Registry.lookup(EyeInTheSky.Claude.AgentRegistry, {:session, session.id})

        port = wait_for_codex_port(worker)
        assert is_pid(port)

        send(
          port,
          {:send_output,
           Jason.encode!(%{
             "type" => "item.completed",
             "item" => %{"type" => "agent_message", "text" => "Scheduler nudge received"}
           })}
        )

        send(
          port,
          {:send_output,
           Jason.encode!(%{
             "type" => "turn.completed",
             "thread_id" => session.uuid,
             "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
           })}
        )

        assert_receive {:new_message, %{body: "Scheduler nudge received"}}, 5_000
        assert Messages.has_inbound_reply?(session.id, "codex")
      after
        case Registry.lookup(EyeInTheSky.Claude.AgentRegistry, {:session, session.id}) do
          [{worker, _}] ->
            DynamicSupervisor.terminate_child(EyeInTheSky.Claude.AgentSupervisor, worker)

          [] ->
            :ok
        end

        Application.put_env(:eye_in_the_sky, :agent_manager_module, previous_manager)
      end
    end

    test "sdk-cli sessions without a worker request delivery rather than only persisting" do
      session =
        create_session(%{provider: "codex", entrypoint: "sdk-cli", managed_by_app: true})

      task = create_task()
      Tasks.link_session_to_task(task.id, session.id)
      assert Registry.lookup(EyeInTheSky.Claude.AgentRegistry, {:session, session.id}) == []

      Process.put(:mock_send_message_response, {:error, :no_worker})
      {_state, failed} = IdleTicketNudger.run_once_for_testing(idle_age_seconds: 60)
      assert failed.failed == 1
      assert failed.sent == 0
      assert Messages.list_inbound_dms(session.id) == []

      Process.put(:mock_send_message_response, {:ok, :sent})
      {_state, delivered} = IdleTicketNudger.run_once_for_testing(idle_age_seconds: 60)
      assert delivered.sent == 1
      assert length(Messages.list_inbound_dms(session.id)) == 1
    end

    test "sends a nudge to an idle session with linked open tasks" do
      Process.put(:mock_send_message_response, {:ok, :sent})

      session = create_session()
      task = create_task()
      Tasks.link_session_to_task(task.id, session.id)

      {_state, stats} = IdleTicketNudger.run_once_for_testing(idle_age_seconds: 60)

      assert stats.sent == 1

      [message] = Messages.list_inbound_dms(session.id)
      assert message.from_session_id == Sessions.ensure_web_ui_session()
      assert message.metadata["source"] == "idle_ticket_nudger"
      assert message.metadata["task_ids"] == [task.id]
      assert message.body =~ "##{task.id}: #{task.title}"
      assert message.body =~ "update status or add notes"
    end

    test "does not nudge sessions without open linked tasks" do
      Process.put(:mock_send_message_response, {:ok, :sent})

      session = create_session()
      done_task = create_task(%{title: "Already done", state_id: Tasks.state_done()})
      archived_task = create_task(%{title: "Archived", archived: true})
      Tasks.link_session_to_task(done_task.id, session.id)
      Tasks.link_session_to_task(archived_task.id, session.id)

      {_state, stats} = IdleTicketNudger.run_once_for_testing(idle_age_seconds: 60)

      assert stats.sent == 0
      assert Messages.list_inbound_dms(session.id) == []
    end

    test "persists terminal-owned nudges without requiring a live app worker" do
      Process.put(:mock_send_message_response, {:error, :no_worker})

      session =
        create_session(%{
          provider: "openai",
          entrypoint: "cli",
          managed_by_app: false
        })

      task = create_task()
      Tasks.link_session_to_task(task.id, session.id)

      {_state, stats} = IdleTicketNudger.run_once_for_testing(idle_age_seconds: 60)

      assert stats.sent == 1
      [message] = Messages.list_inbound_dms(session.id)
      assert message.body =~ "open ticket(s)"
    end

    test "does not resend the same nudge during the cooldown window" do
      Process.put(:mock_send_message_response, {:ok, :sent})

      session = create_session()
      task = create_task()
      Tasks.link_session_to_task(task.id, session.id)

      {_state, first_stats} =
        IdleTicketNudger.run_once_for_testing(idle_age_seconds: 60, cooldown_seconds: 1_800)

      {_state, second_stats} =
        IdleTicketNudger.run_once_for_testing(idle_age_seconds: 60, cooldown_seconds: 1_800)

      assert first_stats.sent == 1
      assert second_stats.sent == 0
      assert second_stats.skipped == 1
      assert length(Messages.list_inbound_dms(session.id)) == 1
    end

    test "does not nudge active or freshly idle sessions" do
      Process.put(:mock_send_message_response, {:ok, :sent})

      task = create_task()

      working = create_session(%{status: "working"})

      fresh =
        create_session(%{
          last_activity_at: DateTime.utc_now(),
          started_at: DateTime.utc_now()
        })

      Tasks.link_session_to_task(task.id, working.id)
      Tasks.link_session_to_task(task.id, fresh.id)

      {_state, stats} = IdleTicketNudger.run_once_for_testing(idle_age_seconds: 60)

      assert stats.sent == 0
      assert Messages.list_inbound_dms(working.id) == []
      assert Messages.list_inbound_dms(fresh.id) == []
    end
  end
end
