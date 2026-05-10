defmodule EyeInTheSky.Sessions.ToolEventRecorderTest do
  use EyeInTheSky.DataCase, async: true

  import EyeInTheSky.Factory

  alias EyeInTheSky.Events
  alias EyeInTheSky.Messages
  alias EyeInTheSky.Sessions.ToolEventRecorder

  describe "record_tool_event/3 with invalid type" do
    test "returns {:error, reason} for unknown type" do
      session = new_session()

      assert {:error, "Invalid type"} =
               ToolEventRecorder.record_tool_event(session, "bogus", %{
                 "tool_name" => "Bash",
                 "tool_input" => %{}
               })
    end

    test "returns {:error, reason} for empty type" do
      session = new_session()
      assert {:error, "Invalid type"} = ToolEventRecorder.record_tool_event(session, "", %{})
    end
  end

  describe "record_tool_event/3 pre event" do
    setup do
      session = new_session()
      Events.subscribe_session(session.id)
      Events.subscribe_agent_working()
      {:ok, session: session}
    end

    test "returns :ok and inserts a Message", %{session: session} do
      params = %{"tool_name" => "Bash", "tool_input" => %{"command" => "ls"}}

      assert :ok = ToolEventRecorder.record_tool_event(session, "pre", params)

      [msg] = Messages.list_messages_for_session(session.id)
      assert msg.sender_role == "tool"
      assert msg.recipient_role == "user"
      assert msg.direction == "inbound"
      assert msg.status == "delivered"
      assert msg.provider == "claude"
      assert msg.body =~ "Tool: Bash"
      assert msg.body =~ "ls"
      assert msg.metadata["stream_type"] == "tool_use"
      assert msg.metadata["tool_name"] == "Bash"
      assert msg.metadata["input"] == %{"command" => "ls"}
    end

    test "broadcasts agent_working and session_tool_use", %{session: session} do
      params = %{"tool_name" => "Read", "tool_input" => %{"path" => "/tmp/x"}}

      assert :ok = ToolEventRecorder.record_tool_event(session, "pre", params)

      assert_receive {:agent_working, ^session}
      assert_receive {:tool_use, "Read", %{"path" => "/tmp/x"}}
    end

    test "uses provider override when supplied", %{session: session} do
      params = %{"tool_name" => "Bash", "tool_input" => %{}, "provider" => "codex"}

      assert :ok = ToolEventRecorder.record_tool_event(session, "pre", params)

      [msg] = Messages.list_messages_for_session(session.id)
      assert msg.provider == "codex"
    end

    test "defaults tool_input to empty map when missing", %{session: session} do
      params = %{"tool_name" => "Bash"}

      assert :ok = ToolEventRecorder.record_tool_event(session, "pre", params)

      [msg] = Messages.list_messages_for_session(session.id)
      assert msg.metadata["input"] == %{}
      assert msg.body =~ "Tool: Bash"
      assert msg.body =~ "{}"

      assert_receive {:tool_use, "Bash", %{}}
    end

    test "truncates body to 4000 characters", %{session: session} do
      huge = String.duplicate("a", 10_000)
      params = %{"tool_name" => "Bash", "tool_input" => %{"data" => huge}}

      assert :ok = ToolEventRecorder.record_tool_event(session, "pre", params)

      [msg] = Messages.list_messages_for_session(session.id)
      assert String.length(msg.body) == 4000
    end

    test "still returns :ok and broadcasts when message insert fails (invalid session_id)" do
      # Use a stub session struct with an id that violates the FK constraint
      # so Messages.create_message returns {:error, changeset}.
      session = new_session()
      bad_session = %{session | id: -1}

      Events.subscribe_agent_working()

      params = %{"tool_name" => "Bash", "tool_input" => %{}}

      assert :ok = ToolEventRecorder.record_tool_event(bad_session, "pre", params)

      assert_receive {:agent_working, ^bad_session}
    end
  end

  describe "record_tool_event/3 post event" do
    setup do
      session = new_session()
      Events.subscribe_session(session.id)
      {:ok, session: session}
    end

    test "returns :ok and inserts a Message with tool_result metadata", %{session: session} do
      params = %{"tool_name" => "Bash", "tool_input" => %{"command" => "echo hi"}}

      assert :ok = ToolEventRecorder.record_tool_event(session, "post", params)

      [msg] = Messages.list_messages_for_session(session.id)
      assert msg.sender_role == "tool"
      assert msg.recipient_role == "user"
      assert msg.direction == "inbound"
      assert msg.status == "delivered"
      assert msg.provider == "claude"
      assert msg.body =~ "Tool: Bash (completed)"
      assert msg.metadata["stream_type"] == "tool_result"
      assert msg.metadata["tool_name"] == "Bash"
      # post does not store input in metadata
      refute Map.has_key?(msg.metadata, "input")
    end

    test "broadcasts session_tool_result with error?=false", %{session: session} do
      params = %{"tool_name" => "Read", "tool_input" => %{}}

      assert :ok = ToolEventRecorder.record_tool_event(session, "post", params)

      assert_receive {:tool_result, "Read", false}
    end

    test "respects provider override", %{session: session} do
      params = %{"tool_name" => "Bash", "tool_input" => %{}, "provider" => "gemini"}

      assert :ok = ToolEventRecorder.record_tool_event(session, "post", params)

      [msg] = Messages.list_messages_for_session(session.id)
      assert msg.provider == "gemini"
    end

    test "defaults tool_input when missing", %{session: session} do
      params = %{"tool_name" => "Bash"}

      assert :ok = ToolEventRecorder.record_tool_event(session, "post", params)

      [msg] = Messages.list_messages_for_session(session.id)
      assert msg.body =~ "Tool: Bash (completed)"
      assert msg.body =~ "{}"
    end

    test "truncates body to 4000 characters", %{session: session} do
      huge = String.duplicate("b", 10_000)
      params = %{"tool_name" => "Bash", "tool_input" => %{"data" => huge}}

      assert :ok = ToolEventRecorder.record_tool_event(session, "post", params)

      [msg] = Messages.list_messages_for_session(session.id)
      assert String.length(msg.body) == 4000
    end

    test "still returns :ok and broadcasts when message insert fails" do
      session = new_session()
      bad_session = %{session | id: -1}
      Events.subscribe_session(bad_session.id)

      params = %{"tool_name" => "Bash", "tool_input" => %{}}

      assert :ok = ToolEventRecorder.record_tool_event(bad_session, "post", params)

      assert_receive {:tool_result, "Bash", false}
    end
  end
end
