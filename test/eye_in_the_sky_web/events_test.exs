defmodule EyeInTheSkyWeb.EventsTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  alias EyeInTheSkyWeb.Events

  @pubsub EyeInTheSkyWeb.PubSub

  # Subscribe directly to PubSub in tests so we verify what Events actually
  # broadcasts, without going through Events.subscribe_* (which is also tested).
  defp sub(topic), do: Phoenix.PubSub.subscribe(@pubsub, topic)

  # ---------------------------------------------------------------------------
  # Subscribe helpers
  # ---------------------------------------------------------------------------

  describe "subscribe helpers" do
    test "subscribe_agents/0 subscribes to agents topic" do
      Events.subscribe_agents()
      Events.agent_updated(%{id: 1})
      assert_receive {:agent_updated, %{id: 1}}, 500
    end

    test "subscribe_agent_working/0 subscribes to agent:working topic" do
      Events.subscribe_agent_working()
      Events.agent_working("ref-1", 42)
      assert_receive {:agent_working, "ref-1", 42}, 500
    end

    test "subscribe_tasks/0 subscribes to tasks topic" do
      Events.subscribe_tasks()
      Events.tasks_changed()
      assert_receive :tasks_changed, 500
    end

    test "subscribe_project_tasks/1 subscribes to tasks:<id> topic" do
      Events.subscribe_project_tasks(99)
      Events.task_updated(%{project_id: 99})
      assert_receive :tasks_changed, 500
    end

    test "subscribe_session/1 subscribes to session:<id> topic" do
      Events.subscribe_session(7)
      Events.session_new_message(7, %{id: 1})
      assert_receive {:new_message, %{id: 1}}, 500
    end

    test "subscribe_session_status/1 subscribes to session:<id>:status topic" do
      Events.subscribe_session_status("uuid-abc")
      Events.session_status("uuid-abc", :working)
      assert_receive {:session_status, "uuid-abc", :working}, 500
    end

    test "subscribe_dm_stream/1 subscribes to dm:<id>:stream topic" do
      Events.subscribe_dm_stream(5)
      Events.stream_clear(5)
      assert_receive :stream_clear, 500
    end

    test "subscribe_dm_queue/1 subscribes to dm:<id>:queue topic" do
      Events.subscribe_dm_queue(5)
      Events.queue_updated(5, [:job1])
      assert_receive {:queue_updated, [:job1]}, 500
    end

    test "subscribe_channel_messages/1 subscribes to channel:<id>:messages topic" do
      Events.subscribe_channel_messages(3)
      Events.channel_message(3, %{body: "hi"})
      assert_receive {:new_message, %{body: "hi"}}, 500
    end

    test "subscribe_notifications/0 subscribes to notifications topic" do
      Events.subscribe_notifications()
      Events.notification(:notification_created, %{id: 10})
      assert_receive {:notification_created, %{id: 10}}, 500
    end

    test "subscribe_teams/0 subscribes to teams topic" do
      Events.subscribe_teams()
      Events.team_event(:team_created, %{id: 1})
      assert_receive {:team_created, %{id: 1}}, 500
    end

    test "subscribe_settings/0 subscribes to settings topic" do
      Events.subscribe_settings()
      Events.settings_changed("theme", "dark")
      assert_receive {:settings_changed, "theme", "dark"}, 500
    end

    test "subscribe_scheduled_jobs/0 subscribes to scheduled_jobs topic" do
      Events.subscribe_scheduled_jobs()
      Events.jobs_updated()
      assert_receive :jobs_updated, 500
    end
  end

  # ---------------------------------------------------------------------------
  # Agent identity events
  # ---------------------------------------------------------------------------

  describe "agent events" do
    test "agent_created/1 broadcasts {:agent_created, agent} to agents topic" do
      sub("agents")
      Events.agent_created(%{id: 1, name: "bot"})
      assert_receive {:agent_created, %{id: 1, name: "bot"}}, 500
    end

    test "agent_updated/1 broadcasts {:agent_updated, agent} to agents topic" do
      sub("agents")
      Events.agent_updated(%{id: 2})
      assert_receive {:agent_updated, %{id: 2}}, 500
    end

    test "agent_deleted/1 broadcasts {:agent_deleted, agent} to agents topic" do
      sub("agents")
      Events.agent_deleted(%{id: 3})
      assert_receive {:agent_deleted, %{id: 3}}, 500
    end
  end

  # ---------------------------------------------------------------------------
  # Session events (required initial set)
  # ---------------------------------------------------------------------------

  describe "session_started/1" do
    test "broadcasts {:agent_updated, session} to agents topic" do
      sub("agents")
      Events.session_started(%{id: 10, status: "working"})
      assert_receive {:agent_updated, %{id: 10, status: "working"}}, 500
    end
  end

  describe "session_updated/1" do
    test "broadcasts {:agent_updated, session} to agents topic" do
      sub("agents")
      Events.session_updated(%{id: 11})
      assert_receive {:agent_updated, %{id: 11}}, 500
    end
  end

  describe "session_output/3" do
    test "broadcasts {:claude_response, ref, parsed} to session:<id> topic" do
      sub("session:20")
      ref = make_ref()
      Events.session_output(20, ref, %{type: "text"})
      assert_receive {:claude_response, ^ref, %{type: "text"}}, 500
    end
  end

  describe "session_completed/1" do
    test "broadcasts {:agent_stopped, session} to agents topic" do
      sub("agents")
      Events.session_completed(%{id: 12, status: "completed"})
      assert_receive {:agent_stopped, %{id: 12}}, 500
    end
  end

  describe "session_failed/2" do
    test "broadcasts {:agent_stopped, session} to agents topic" do
      sub("agents")
      Events.session_failed(%{id: 13}, :timeout)
      assert_receive {:agent_stopped, %{id: 13}}, 500
    end
  end

  # ---------------------------------------------------------------------------
  # Agent working status
  # ---------------------------------------------------------------------------

  describe "agent_working/2" do
    test "broadcasts {:agent_working, ref, int_id} to agent:working topic" do
      sub("agent:working")
      Events.agent_working("uuid-ref", 99)
      assert_receive {:agent_working, "uuid-ref", 99}, 500
    end
  end

  describe "agent_working/1" do
    test "broadcasts {:agent_working, session} to agent:working topic" do
      sub("agent:working")
      Events.agent_working(%{id: 5})
      assert_receive {:agent_working, %{id: 5}}, 500
    end
  end

  describe "agent_stopped/2" do
    test "broadcasts {:agent_stopped, ref, int_id} to agent:working topic" do
      sub("agent:working")
      Events.agent_stopped("uuid-ref", 99)
      assert_receive {:agent_stopped, "uuid-ref", 99}, 500
    end
  end

  describe "agent_stopped/1" do
    test "broadcasts {:agent_stopped, session} to agent:working topic" do
      sub("agent:working")
      Events.agent_stopped(%{id: 5})
      assert_receive {:agent_stopped, %{id: 5}}, 500
    end
  end

  # ---------------------------------------------------------------------------
  # Session message events
  # ---------------------------------------------------------------------------

  describe "session_new_message/2" do
    test "broadcasts {:new_message, msg} to session:<id> topic" do
      sub("session:30")
      Events.session_new_message(30, %{id: 100})
      assert_receive {:new_message, %{id: 100}}, 500
    end
  end

  describe "session_new_dm/2" do
    test "broadcasts {:new_dm, msg} to session:<id> topic" do
      sub("session:31")
      Events.session_new_dm(31, %{id: 200})
      assert_receive {:new_dm, %{id: 200}}, 500
    end
  end

  describe "session_cli_complete/3" do
    test "broadcasts {:claude_complete, ref, exit_code} to session:<id> topic" do
      sub("session:32")
      ref = make_ref()
      Events.session_cli_complete(32, ref, 0)
      assert_receive {:claude_complete, ^ref, 0}, 500
    end
  end

  describe "session_tool_use/3" do
    test "broadcasts {:tool_use, name, input} to session:<id> topic" do
      sub("session:33")
      Events.session_tool_use(33, "Bash", %{"command" => "ls"})
      assert_receive {:tool_use, "Bash", %{"command" => "ls"}}, 500
    end
  end

  describe "session_tool_result/3" do
    test "broadcasts {:tool_result, name, error?} to session:<id> topic" do
      sub("session:34")
      Events.session_tool_result(34, "Bash", false)
      assert_receive {:tool_result, "Bash", false}, 500
    end
  end

  # ---------------------------------------------------------------------------
  # Session status
  # ---------------------------------------------------------------------------

  describe "session_status/2" do
    test "broadcasts {:session_status, id, status} to session:<id>:status topic" do
      sub("session:uuid-xyz:status")
      Events.session_status("uuid-xyz", :idle)
      assert_receive {:session_status, "uuid-xyz", :idle}, 500
    end
  end

  # ---------------------------------------------------------------------------
  # Stream events
  # ---------------------------------------------------------------------------

  describe "stream_event/2" do
    test "broadcasts event to dm:<id>:stream topic" do
      sub("dm:40:stream")
      Events.stream_event(40, {:stream_delta, :text, "hello"})
      assert_receive {:stream_delta, :text, "hello"}, 500
    end
  end

  describe "stream_clear/1" do
    test "broadcasts :stream_clear to dm:<id>:stream topic" do
      sub("dm:41:stream")
      Events.stream_clear(41)
      assert_receive :stream_clear, 500
    end
  end

  describe "stream_error/3" do
    test "broadcasts {:agent_error, provider_id, session_id, reason} to dm:<id>:stream topic" do
      sub("dm:42:stream")
      Events.stream_error(42, "conv-ref", "timeout")
      assert_receive {:agent_error, "conv-ref", 42, "timeout"}, 500
    end
  end

  # ---------------------------------------------------------------------------
  # Queue events
  # ---------------------------------------------------------------------------

  describe "queue_updated/2" do
    test "broadcasts {:queue_updated, queue} to dm:<id>:queue topic" do
      sub("dm:50:queue")
      Events.queue_updated(50, ["job1", "job2"])
      assert_receive {:queue_updated, ["job1", "job2"]}, 500
    end
  end

  # ---------------------------------------------------------------------------
  # Channel events
  # ---------------------------------------------------------------------------

  describe "channel_message/2" do
    test "broadcasts {:new_message, msg} to channel:<id>:messages topic" do
      sub("channel:10:messages")
      Events.channel_message(10, %{body: "hello"})
      assert_receive {:new_message, %{body: "hello"}}, 500
    end
  end

  # ---------------------------------------------------------------------------
  # Task events
  # ---------------------------------------------------------------------------

  describe "task_updated/1" do
    test "broadcasts :tasks_changed to global tasks topic" do
      sub("tasks")
      Events.task_updated(%{project_id: nil})
      assert_receive :tasks_changed, 500
    end

    test "also broadcasts :tasks_changed to tasks:<project_id> when project_id set" do
      sub("tasks:77")
      Events.task_updated(%{project_id: 77})
      assert_receive :tasks_changed, 500
    end

    test "does not broadcast to a different project topic" do
      sub("tasks:88")
      Events.task_updated(%{project_id: 77})
      refute_receive :tasks_changed, 200
    end
  end

  describe "tasks_changed/0" do
    test "broadcasts :tasks_changed to global tasks topic only" do
      sub("tasks")
      Events.tasks_changed()
      assert_receive :tasks_changed, 500
    end
  end

  # ---------------------------------------------------------------------------
  # Notification events
  # ---------------------------------------------------------------------------

  describe "notification/2" do
    test "broadcasts {event, payload} to notifications topic" do
      sub("notifications")
      Events.notification(:notification_created, %{id: 5})
      assert_receive {:notification_created, %{id: 5}}, 500
    end

    test "notification/1 broadcasts {event, nil} when no payload given" do
      sub("notifications")
      Events.notification(:notifications_updated)
      assert_receive {:notifications_updated, nil}, 500
    end
  end

  # ---------------------------------------------------------------------------
  # Team events
  # ---------------------------------------------------------------------------

  describe "team_event/2" do
    test "broadcasts {event, payload} to teams topic" do
      sub("teams")
      Events.team_event(:team_created, %{id: 1})
      assert_receive {:team_created, %{id: 1}}, 500
    end
  end

  # ---------------------------------------------------------------------------
  # Settings events
  # ---------------------------------------------------------------------------

  describe "settings_changed/2" do
    test "broadcasts {:settings_changed, key, value} to settings topic" do
      sub("settings")
      Events.settings_changed("theme", "dark")
      assert_receive {:settings_changed, "theme", "dark"}, 500
    end
  end

  # ---------------------------------------------------------------------------
  # Scheduled job events
  # ---------------------------------------------------------------------------

  describe "jobs_updated/0" do
    test "broadcasts :jobs_updated to scheduled_jobs topic" do
      sub("scheduled_jobs")
      Events.jobs_updated()
      assert_receive :jobs_updated, 500
    end
  end

  # ---------------------------------------------------------------------------
  # Topic isolation — verify events don't bleed into wrong topics
  # ---------------------------------------------------------------------------

  describe "topic isolation" do
    test "session events don't bleed to agents topic" do
      sub("agents")
      Events.session_new_message(99, %{id: 1})
      refute_receive {:new_message, _}, 200
    end

    test "tasks_changed does not go to project-scoped topic" do
      sub("tasks:55")
      Events.tasks_changed()
      refute_receive :tasks_changed, 200
    end

    test "channel_message for one channel doesn't reach another" do
      sub("channel:20:messages")
      Events.channel_message(21, %{body: "wrong channel"})
      refute_receive {:new_message, _}, 200
    end

    test "stream events for one session don't reach another" do
      sub("dm:60:stream")
      Events.stream_clear(61)
      refute_receive :stream_clear, 200
    end
  end
end
