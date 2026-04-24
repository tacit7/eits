defmodule EyeInTheSky.Claude.AgentWorkerBroadcastIsolationTest do
  use EyeInTheSky.DataCase, async: false

  @moduletag :capture_log

  alias EyeInTheSky.{Agents, PubSub, Sessions}
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Claude.{AgentRegistry, AgentSupervisor, AgentWorker, SDK}

  setup do
    test_pid = self()
    Agent.start(fn -> [] end, name: :"iso_test_sessions_#{inspect(test_pid)}")

    on_exit(fn ->
      session_ids = Agent.get(:"iso_test_sessions_#{inspect(test_pid)}", & &1)

      Enum.each(session_ids, fn session_id ->
        case Registry.lookup(AgentRegistry, {:session, session_id}) do
          [{pid, _}] when is_pid(pid) ->
            DynamicSupervisor.terminate_child(AgentSupervisor, pid)

          _ ->
            :ok
        end
      end)

      Agent.stop(:"iso_test_sessions_#{inspect(test_pid)}", :normal, 1000)
    end)

    {:ok, track: :"iso_test_sessions_#{inspect(test_pid)}"}
  end

  test "worker mailbox is not blocked by slow PubSub subscriber", %{track: track} do
    {:ok, agent} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Isolation Test Agent",
        source: "test"
      })

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        name: "Isolation Test Session",
        provider: "claude",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        git_worktree_path: File.cwd!()
      })

    Agent.update(track, fn ids -> [session.id | ids] end)

    # Subscribe to the stream topic — simulating a slow subscriber that won't
    # drain its mailbox promptly.
    Phoenix.PubSub.subscribe(PubSub, "dm:#{session.id}:stream")
    Phoenix.PubSub.subscribe(PubSub, "agent:working")

    # Start the worker with a job.
    assert {:ok, :started} = AgentManager.send_message(session.id, "hello")
    assert_receive {:agent_working, _}, 5_000

    mock_port = wait_for_mock_port(session.id)
    assert mock_port != nil

    # Feed the worker a stream event via the mock SDK port.
    delta_json = Jason.encode!(%{"type" => "text", "content" => "hello"})
    send(mock_port, {:send_output, delta_json})

    # Simulate a slow subscriber: sleep 200ms without consuming our mailbox.
    # If broadcast_events were synchronous in the GenServer's handle_info,
    # it could delay processing the next GenServer message.
    Process.sleep(200)

    # The worker's GenServer mailbox must still be processing unrelated messages
    # within 50ms — confirming the broadcast ran in a supervised Task, not inline.
    [{worker_pid, _}] = Registry.lookup(AgentRegistry, {:session, session.id})

    # :sys.get_state/2 with a 50ms timeout is a GenServer.call under the hood;
    # it would time out if the worker's loop were blocked.
    worker_state = :sys.get_state(worker_pid, 50)
    assert %AgentWorker{} = worker_state

    # Clean up.
    send(mock_port, {:exit, 0})
  end

  # Helpers (mirrored from AgentWorkerTest — not shared yet)

  defp wait_for_mock_port(session_id, attempts \\ 20)
  defp wait_for_mock_port(_session_id, 0), do: nil

  defp wait_for_mock_port(session_id, attempts) do
    case Registry.lookup(AgentRegistry, {:session, session_id}) do
      [{worker_pid, _}] when is_pid(worker_pid) ->
        if Process.alive?(worker_pid) do
          state = :sys.get_state(worker_pid)
          sdk_ref = state.sdk_ref

          if sdk_ref do
            case SDK.Registry.lookup(sdk_ref) do
              nil ->
                Process.sleep(50)
                wait_for_mock_port(session_id, attempts - 1)

              mock_port ->
                mock_port
            end
          else
            Process.sleep(50)
            wait_for_mock_port(session_id, attempts - 1)
          end
        else
          Process.sleep(50)
          wait_for_mock_port(session_id, attempts - 1)
        end

      [] ->
        Process.sleep(50)
        wait_for_mock_port(session_id, attempts - 1)
    end
  end
end
