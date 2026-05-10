defmodule EyeInTheSkyWeb.DmLive.AgentLifecycleTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.Factory
  alias EyeInTheSkyWeb.DmLive.AgentLifecycle

  # push_event/3 writes to socket.private.live_temp[:push_events] as [[name, payload], ...]
  # so private must have live_temp: %{} or the update_in crashes.
  defp build_socket(assigns) do
    base = %{__changed__: %{}, flash: %{}}

    %Phoenix.LiveView.Socket{
      private: %{live_temp: %{}},
      assigns: Map.merge(base, assigns)
    }
  end

  # Reads [[event_name, payload], ...] from the path push_event/3 writes to.
  defp push_events(socket) do
    (socket.private[:live_temp] || %{})[:push_events] || []
  end

  defp assert_push_event(socket, event_name) do
    events = push_events(socket)

    assert Enum.any?(events, fn
             [^event_name | _] -> true
             _ -> false
           end),
           "Expected push_event '#{event_name}' to be in #{inspect(events)}"
  end

  # sync_and_reload/1 calls sync_messages_from_session_file/1 which reads
  # socket.assigns.session.provider. Setting provider: "gemini" makes it
  # return {:ok, socket, 0} immediately — no agent, session_uuid, or file
  # system access needed.
  defp gemini_session(session), do: %{session | provider: "gemini"}

  describe "handle_claude_response/3" do
    test "sets processing to false" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          session: gemini_session(session),
          processing: true,
          active_tab: "messages"
        })

      {:noreply, result} =
        AgentLifecycle.handle_claude_response("ref_123", %{"type" => "assistant"}, socket)

      assert result.assigns.processing == false
    end

    test "pushes focus-input event" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          session: gemini_session(session),
          processing: true,
          active_tab: "messages"
        })

      {:noreply, result} =
        AgentLifecycle.handle_claude_response("ref_123", %{"type" => "assistant"}, socket)

      assert_push_event(result, "focus-input")
    end

    test "accepts any response type" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          session: gemini_session(session),
          processing: true,
          active_tab: "messages"
        })

      {:noreply, result} =
        AgentLifecycle.handle_claude_response("ref_123", %{"type" => "tool_use"}, socket)

      assert result.assigns.processing == false
    end
  end

  describe "handle_claude_complete/3" do
    test "sets processing to false and clears session_ref" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          session: gemini_session(session),
          session_ref: "ref_123",
          processing: true,
          active_tab: "messages"
        })

      {:noreply, result} = AgentLifecycle.handle_claude_complete("ref_123", 0, socket)

      assert result.assigns.processing == false
      assert result.assigns.session_ref == nil
    end

    test "pushes focus-input event" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          session: gemini_session(session),
          session_ref: "ref_123",
          processing: true,
          active_tab: "messages"
        })

      {:noreply, result} = AgentLifecycle.handle_claude_complete("ref_123", 0, socket)

      assert_push_event(result, "focus-input")
    end

    test "handles non-zero exit codes the same as zero" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          session: gemini_session(session),
          session_ref: "ref_123",
          processing: true,
          active_tab: "messages"
        })

      {:noreply, result} = AgentLifecycle.handle_claude_complete("ref_123", 1, socket)

      assert result.assigns.processing == false
      assert result.assigns.session_ref == nil
    end
  end

  describe "handle_agent_working/2" do
    test "sets processing to true and compacting to false for working status" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          compacting: false,
          processing: false
        })

      {:noreply, result} =
        AgentLifecycle.handle_agent_working(%{id: session.id, status: "working"}, socket)

      assert result.assigns.processing == true
      assert result.assigns.compacting == false
    end

    test "sets compacting to true when status is compacting" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          compacting: false,
          processing: false
        })

      {:noreply, result} =
        AgentLifecycle.handle_agent_working(%{id: session.id, status: "compacting"}, socket)

      assert result.assigns.compacting == true
    end

    test "ignores messages for a different session_id" do
      session = Factory.new_session()
      other_id = System.unique_integer([:positive])

      socket =
        build_socket(%{
          session_id: session.id,
          compacting: false,
          processing: false
        })

      {:noreply, result} =
        AgentLifecycle.handle_agent_working(%{id: other_id, status: "working"}, socket)

      assert result.assigns.processing == false
      assert result.assigns.compacting == false
    end

    test "non-compacting status sets processing to true" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          compacting: true,
          processing: false
        })

      {:noreply, result} =
        AgentLifecycle.handle_agent_working(%{id: session.id, status: "idle"}, socket)

      assert result.assigns.processing == true
      assert result.assigns.compacting == false
    end
  end

  describe "handle_agent_stopped/2" do
    test "sets processing and compacting to false" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          session: gemini_session(session),
          compacting: true,
          processing: true,
          notify_on_stop: false,
          active_tab: "messages"
        })

      {:noreply, result} = AgentLifecycle.handle_agent_stopped(%{id: session.id}, socket)

      assert result.assigns.processing == false
      assert result.assigns.compacting == false
    end

    test "pushes focus-input event" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          session: gemini_session(session),
          compacting: true,
          processing: true,
          notify_on_stop: false,
          active_tab: "messages"
        })

      {:noreply, result} = AgentLifecycle.handle_agent_stopped(%{id: session.id}, socket)

      assert_push_event(result, "focus-input")
    end

    test "ignores messages for a different session_id" do
      session = Factory.new_session()
      other_id = System.unique_integer([:positive])

      socket =
        build_socket(%{
          session_id: session.id,
          session: gemini_session(session),
          compacting: true,
          processing: true,
          notify_on_stop: false,
          active_tab: "messages"
        })

      {:noreply, result} = AgentLifecycle.handle_agent_stopped(%{id: other_id}, socket)

      assert result.assigns.processing == true
      assert result.assigns.compacting == true
    end

    test "does not crash when notify_on_stop is false and desktop mode is off" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          session: gemini_session(session),
          compacting: false,
          processing: true,
          notify_on_stop: false,
          active_tab: "messages"
        })

      assert {:noreply, _} = AgentLifecycle.handle_agent_stopped(%{id: session.id}, socket)
    end
  end

  describe "handle_agent_updated/2" do
    test "updates session and session_status when id matches" do
      session = Factory.new_session()
      updated = %{session | status: "completed"}

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          session_status: "working",
          processing: true,
          compacting: false
        })

      {:noreply, result} = AgentLifecycle.handle_agent_updated(updated, socket)

      assert result.assigns.session.id == session.id
      assert result.assigns.session_status == "completed"
    end

    test "syncs processing=true from working status" do
      session = Factory.new_session()
      updated = %{session | status: "working"}

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          processing: false,
          compacting: true
        })

      {:noreply, result} = AgentLifecycle.handle_agent_updated(updated, socket)

      assert result.assigns.processing == true
      assert result.assigns.compacting == false
    end

    test "syncs compacting=true from compacting status" do
      session = Factory.new_session()
      updated = %{session | status: "compacting"}

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          processing: false,
          compacting: false
        })

      {:noreply, result} = AgentLifecycle.handle_agent_updated(updated, socket)

      assert result.assigns.compacting == true
    end

    test "syncs processing=false from completed status" do
      session = Factory.new_session()
      updated = %{session | status: "completed"}

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          processing: true,
          compacting: false
        })

      {:noreply, result} = AgentLifecycle.handle_agent_updated(updated, socket)

      assert result.assigns.processing == false
      assert result.assigns.compacting == false
    end

    test "syncs processing=false from failed status" do
      session = Factory.new_session()
      updated = %{session | status: "failed"}

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          processing: true,
          compacting: true
        })

      {:noreply, result} = AgentLifecycle.handle_agent_updated(updated, socket)

      assert result.assigns.processing == false
      assert result.assigns.compacting == false
    end

    test "syncs processing=false from idle status" do
      session = Factory.new_session()
      updated = %{session | status: "idle"}

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          processing: true,
          compacting: false
        })

      {:noreply, result} = AgentLifecycle.handle_agent_updated(updated, socket)

      assert result.assigns.processing == false
    end

    test "syncs processing=false from waiting status" do
      session = Factory.new_session()
      updated = %{session | status: "waiting"}

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          processing: true,
          compacting: false
        })

      {:noreply, result} = AgentLifecycle.handle_agent_updated(updated, socket)

      assert result.assigns.processing == false
    end

    test "ignores updates for a different session_id" do
      session = Factory.new_session()
      other = Factory.new_session()
      updated = %{other | status: "completed"}

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          processing: true,
          compacting: false
        })

      {:noreply, result} = AgentLifecycle.handle_agent_updated(updated, socket)

      assert result.assigns.session.id == session.id
      assert result.assigns.processing == true
    end

    test "unknown status leaves processing/compacting unchanged" do
      session = Factory.new_session()
      updated = %{session | status: "unknown_status"}

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          processing: true,
          compacting: true
        })

      {:noreply, result} = AgentLifecycle.handle_agent_updated(updated, socket)

      assert result.assigns.processing == true
      assert result.assigns.compacting == true
    end
  end

  describe "handle_tasks_changed/1" do
    test "updates current_task assign from the database" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          current_task: :some_previous_value
        })

      {:noreply, result} = AgentLifecycle.handle_tasks_changed(socket)

      # Session has no tasks — result should be nil (not :some_previous_value)
      assert result.assigns.current_task == nil
    end

    test "returns :noreply tuple" do
      session = Factory.new_session()

      socket = build_socket(%{session_id: session.id, current_task: nil})

      assert {:noreply, _socket} = AgentLifecycle.handle_tasks_changed(socket)
    end
  end
end
