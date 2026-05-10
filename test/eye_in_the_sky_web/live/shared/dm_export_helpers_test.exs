defmodule EyeInTheSkyWeb.Live.Shared.DmExportHelpersTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.Factory
  alias EyeInTheSkyWeb.Live.Shared.DmExportHelpers

  # push_event stores queued events in socket.private.live_temp[:push_events]
  defp push_events(socket), do: socket.private.live_temp[:push_events] || []

  defp build_socket(assigns) do
    base = %{
      __changed__: %{},
      flash: %{}
    }

    %Phoenix.LiveView.Socket{
      private: %{live_temp: %{}},
      assigns: Map.merge(base, assigns)
    }
  end

  defp message_fixture(role, body, inserted_at \\ ~U[2024-01-01 00:00:00Z]) do
    %{
      sender_role: role,
      body: body,
      inserted_at: inserted_at
    }
  end

  describe "handle_export_jsonl/1" do
    test "pushes copy_to_clipboard event with JSONL format" do
      msg = message_fixture("user", "Hello")
      socket = build_socket(%{messages: [msg]})

      {:noreply, result} = DmExportHelpers.handle_export_jsonl(socket)

      events = push_events(result)
      assert length(events) == 1
      [["copy_to_clipboard", payload]] = events
      assert payload.format == "JSONL"
    end

    test "encodes each message as a JSON object on its own line" do
      msgs = [
        message_fixture("user", "first"),
        message_fixture("assistant", "second")
      ]

      socket = build_socket(%{messages: msgs})
      {:noreply, result} = DmExportHelpers.handle_export_jsonl(socket)

      [["copy_to_clipboard", payload]] = push_events(result)
      lines = String.split(payload.text, "\n")
      assert length(lines) == 2

      first = Jason.decode!(Enum.at(lines, 0))
      assert first["role"] == "user"
      assert first["body"] == "first"

      second = Jason.decode!(Enum.at(lines, 1))
      assert second["role"] == "assistant"
      assert second["body"] == "second"
    end

    test "produces empty string when messages list is empty" do
      socket = build_socket(%{messages: []})
      {:noreply, result} = DmExportHelpers.handle_export_jsonl(socket)

      [["copy_to_clipboard", payload]] = push_events(result)
      assert payload.text == ""
    end

    test "works when :messages assign is absent (nil guard)" do
      socket = build_socket(%{})
      {:noreply, result} = DmExportHelpers.handle_export_jsonl(socket)

      [["copy_to_clipboard", payload]] = push_events(result)
      assert payload.text == ""
    end
  end

  describe "handle_export_markdown/1" do
    test "pushes copy_to_clipboard event with Markdown format" do
      msg = message_fixture("user", "Hello")
      socket = build_socket(%{messages: [msg]})

      {:noreply, result} = DmExportHelpers.handle_export_markdown(socket)

      events = push_events(result)
      assert length(events) == 1
      [["copy_to_clipboard", payload]] = events
      assert payload.format == "Markdown"
    end

    test "formats each message as bolded role followed by body" do
      msgs = [
        message_fixture("user", "what is 2+2"),
        message_fixture("assistant", "4")
      ]

      socket = build_socket(%{messages: msgs})
      {:noreply, result} = DmExportHelpers.handle_export_markdown(socket)

      [["copy_to_clipboard", payload]] = push_events(result)
      assert payload.text =~ "**User**: what is 2+2"
      assert payload.text =~ "**Assistant**: 4"
    end

    test "separates messages with double newline" do
      msgs = [
        message_fixture("user", "one"),
        message_fixture("assistant", "two")
      ]

      socket = build_socket(%{messages: msgs})
      {:noreply, result} = DmExportHelpers.handle_export_markdown(socket)

      [["copy_to_clipboard", payload]] = push_events(result)
      assert payload.text =~ "\n\n"
    end

    test "produces empty string when messages list is empty" do
      socket = build_socket(%{messages: []})
      {:noreply, result} = DmExportHelpers.handle_export_markdown(socket)

      [["copy_to_clipboard", payload]] = push_events(result)
      assert payload.text == ""
    end

    test "works when :messages assign is absent (nil guard)" do
      socket = build_socket(%{})
      {:noreply, result} = DmExportHelpers.handle_export_markdown(socket)

      [["copy_to_clipboard", payload]] = push_events(result)
      assert payload.text == ""
    end
  end

  describe "handle_reload_from_session_file/2 — gemini provider" do
    test "returns info flash without calling any file reader for gemini sessions" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent, %{provider: "gemini"})

      socket =
        build_socket(%{
          session: session,
          session_id: session.id,
          session_uuid: session.uuid,
          agent: agent
        })

      load_fn = fn s -> s end

      {:noreply, result} = DmExportHelpers.handle_reload_from_session_file(socket, load_fn)

      assert result.assigns.flash["info"] =~ "database"
    end
  end

  describe "handle_reload_from_session_file/2 — claude provider, no project path" do
    test "returns error flash when session has no project path configured" do
      agent = Factory.create_agent()

      session =
        Factory.create_session(agent, %{
          provider: "claude",
          git_worktree_path: nil
        })

      # agent.project will be nil since no project was created; agent.git_worktree_path is nil
      agent = %{agent | git_worktree_path: nil, project: nil}

      socket =
        build_socket(%{
          session: session,
          session_id: session.id,
          session_uuid: session.uuid,
          agent: agent
        })

      load_fn = fn s -> s end

      {:noreply, result} = DmExportHelpers.handle_reload_from_session_file(socket, load_fn)

      assert result.assigns.flash["error"] =~ "project path"
    end
  end
end
