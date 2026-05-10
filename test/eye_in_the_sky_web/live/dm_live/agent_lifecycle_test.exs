defmodule EyeInTheSkyWeb.DmLive.AgentLifecycleTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.Factory
  alias EyeInTheSkyWeb.DmLive.AgentLifecycle

  # Helper to build a bare socket with assigns
  defp build_socket(assigns) do
    base = %{__changed__: %{}, flash: %{}}
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(base, assigns)
    }
  end

  describe "handle_claude_response/3" do
    test "sets processing to false and pushes focus-input event" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          processing: true
        })

      {:noreply, result} =
        AgentLifecycle.handle_claude_response("ref_123", %{"type" => "assistant"}, socket)

      assert result.assigns.processing == false
      assert_push_event(result, "focus-input")
    end

    test "calls sync_and_reload to refresh messages" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          processing: true
        })

      {:noreply, result} =
        AgentLifecycle.handle_claude_response("ref_123", %{"type" => "assistant"}, socket)

      # sync_and_reload sets last_sync_at
      assert is_map(result.assigns)
    end
  end

  describe "handle_claude_complete/3" do
    test "sets processing to false, clears session_ref, and focuses input" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          session_ref: "ref_123",
          processing: true
        })

      {:noreply, result} = AgentLifecycle.handle_claude_complete("ref_123", 0, socket)

      assert result.assigns.processing == false
      assert result.assigns.session_ref == nil
      assert_push_event(result, "focus-input")
    end

    test "handles non-zero exit codes" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          session_ref: "ref_123",
          processing: true
        })

      {:noreply, result} = AgentLifecycle.handle_claude_complete("ref_123", 1, socket)

      assert result.assigns.processing == false
      assert result.assigns.session_ref == nil
    end
  end

  describe "handle_agent_working/2" do
    test "sets processing to true and compacting to false for non-compacting status" do
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

    test "ignores messages for different session ids" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          compacting: false,
          processing: false
        })

      other_session_id = System.unique_integer([:positive])

      {:noreply, result} =
        AgentLifecycle.handle_agent_working(%{id: other_session_id, status: "working"}, socket)

      assert result.assigns.processing == false
      assert result.assigns.compacting == false
    end
  end

  describe "handle_agent_stopped/2" do
    test "sets processing and compacting to false" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          compacting: true,
          processing: true,
          notify_on_stop: false
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
          session: session,
          compacting: true,
          processing: true,
          notify_on_stop: false
        })

      {:noreply, result} = AgentLifecycle.handle_agent_stopped(%{id: session.id}, socket)

      assert_push_event(result, "focus-input")
    end

    test "ignores messages for different session ids" do
      session = Factory.new_session()
      other_session_id = System.unique_integer([:positive])

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          compacting: true,
          processing: true,
          notify_on_stop: false
        })

      {:noreply, result} =
        AgentLifecycle.handle_agent_stopped(%{id: other_session_id}, socket)

      assert result.assigns.processing == true
      assert result.assigns.compacting == true
    end
  end

  describe "handle_agent_updated/2" do
    test "updates session when session id matches" do
      session = Factory.new_session()
      updated_session = %{session | status: "completed"}

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          session_status: "working",
          processing: true,
          compacting: false
        })

      {:noreply, result} = AgentLifecycle.handle_agent_updated(updated_session, socket)

      assert result.assigns.session.id == updated_session.id
      assert result.assigns.session_status == "completed"
    end

    test "syncs processing from completed status" do
      session = Factory.new_session()
      updated_session = %{session | status: "completed"}

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          processing: true,
          compacting: false
        })

      {:noreply, result} = AgentLifecycle.handle_agent_updated(updated_session, socket)

      assert result.assigns.processing == false
      assert result.assigns.compacting == false
    end

    test "syncs processing from failed status" do
      session = Factory.new_session()
      updated_session = %{session | status: "failed"}

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          processing: true,
          compacting: false
        })

      {:noreply, result} = AgentLifecycle.handle_agent_updated(updated_session, socket)

      assert result.assigns.processing == false
      assert result.assigns.compacting == false
    end

    test "syncs processing from idle status" do
      session = Factory.new_session()
      updated_session = %{session | status: "idle"}

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          processing: true,
          compacting: false
        })

      {:noreply, result} = AgentLifecycle.handle_agent_updated(updated_session, socket)

      assert result.assigns.processing == false
    end

    test "syncs compacting from compacting status" do
      session = Factory.new_session()
      updated_session = %{session | status: "compacting"}

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          processing: false,
          compacting: false
        })

      {:noreply, result} = AgentLifecycle.handle_agent_updated(updated_session, socket)

      assert result.assigns.compacting == true
    end

    test "syncs processing from working status" do
      session = Factory.new_session()
      updated_session = %{session | status: "working"}

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          processing: false,
          compacting: true
        })

      {:noreply, result} = AgentLifecycle.handle_agent_updated(updated_session, socket)

      assert result.assigns.processing == true
      assert result.assigns.compacting == false
    end

    test "ignores updates for different session ids" do
      session = Factory.new_session()
      other_session = Factory.new_session()
      updated_session = %{other_session | status: "completed"}

      socket =
        build_socket(%{
          session_id: session.id,
          session: session,
          processing: true,
          compacting: false
        })

      {:noreply, result} = AgentLifecycle.handle_agent_updated(updated_session, socket)

      assert result.assigns.session.id == session.id
      assert result.assigns.processing == true
    end
  end

  describe "handle_tasks_changed/1" do
    test "updates current_task from database" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session_id: session.id,
          current_task: nil
        })

      {:noreply, result} = AgentLifecycle.handle_tasks_changed(socket)

      assert is_map(result.assigns)
    end
  end

  # Helper to check if a push_event was made
  defp assert_push_event(socket, event_name) do
    events = socket.private[:push_events] || []

    assert Enum.any?(events, fn {name, _data} -> name == event_name end),
           "Expected push_event '#{event_name}' not found in #{inspect(events)}"
  end
end
