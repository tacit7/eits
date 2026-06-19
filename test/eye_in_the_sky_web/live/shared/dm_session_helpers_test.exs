defmodule EyeInTheSkyWeb.Live.Shared.DmSessionHelpersTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.{Factory, Notes, Sessions}
  alias EyeInTheSkyWeb.Live.Shared.DmSessionHelpers

  defp build_socket(assigns) do
    base = %{
      __changed__: %{},
      flash: %{}
    }

    %Phoenix.LiveView.Socket{assigns: Map.merge(base, assigns)}
  end

  defp create_note(session_id) do
    {:ok, note} =
      Notes.create_note(%{
        parent_type: "session",
        parent_id: to_string(session_id),
        body: "test note body #{System.unique_integer([:positive])}"
      })

    note
  end

  describe "handle_update_session_name/2" do
    test "persists name and updates socket assigns on success" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      socket = build_socket(%{session: session})

      {:noreply, result} =
        DmSessionHelpers.handle_update_session_name(%{"value" => "New Name"}, socket)

      assert result.assigns.session.name == "New Name"
      assert result.assigns.page_title == "New Name"
    end

    test "sets name to nil when value is blank" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent, %{name: "Old Name"})
      socket = build_socket(%{session: session})

      {:noreply, result} =
        DmSessionHelpers.handle_update_session_name(%{"value" => "   "}, socket)

      assert result.assigns.session.name == nil
      assert result.assigns.page_title == "Session"
    end

    test "trims whitespace before persisting" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      socket = build_socket(%{session: session})

      {:noreply, result} =
        DmSessionHelpers.handle_update_session_name(%{"value" => "  Trimmed  "}, socket)

      assert result.assigns.session.name == "Trimmed"
    end

    test "persists updated name to database" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      socket = build_socket(%{session: session})

      DmSessionHelpers.handle_update_session_name(%{"value" => "Persisted"}, socket)

      {:ok, reloaded} = Sessions.get_session(session.id)
      assert reloaded.name == "Persisted"
    end
  end

  describe "handle_update_session_description/2" do
    test "persists description and updates socket assigns on success" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      socket = build_socket(%{session: session})

      {:noreply, result} =
        DmSessionHelpers.handle_update_session_description(
          %{"value" => "A new description"},
          socket
        )

      assert result.assigns.session.description == "A new description"
    end

    test "sets description to nil when value is blank" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent, %{description: "Old description"})
      socket = build_socket(%{session: session})

      {:noreply, result} =
        DmSessionHelpers.handle_update_session_description(%{"value" => ""}, socket)

      assert result.assigns.session.description == nil
    end

    test "trims whitespace from description before persisting" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      socket = build_socket(%{session: session})

      {:noreply, result} =
        DmSessionHelpers.handle_update_session_description(
          %{"value" => "  padded  "},
          socket
        )

      assert result.assigns.session.description == "padded"
    end

    test "persists updated description to database" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      socket = build_socket(%{session: session})

      DmSessionHelpers.handle_update_session_description(
        %{"value" => "Persisted description"},
        socket
      )

      {:ok, reloaded} = Sessions.get_session(session.id)
      assert reloaded.description == "Persisted description"
    end
  end

  describe "handle_toggle_star/3" do
    test "invokes load_notes_fn after toggling star on a note" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      note = create_note(session.id)
      socket = build_socket(%{})

      reload_called = :ets.new(:reload_flag, [:set, :public])
      :ets.insert(reload_called, {:called, false})

      load_fn = fn s ->
        :ets.insert(reload_called, {:called, true})
        s
      end

      {:noreply, _result} =
        DmSessionHelpers.handle_toggle_star(%{"note_id" => note.id}, socket, load_fn)

      [{:called, was_called}] = :ets.lookup(reload_called, :called)
      assert was_called == true
    end

    test "accepts note_id from note-id key" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      note = create_note(session.id)
      socket = build_socket(%{})

      load_fn = fn s -> s end

      {:noreply, _result} =
        DmSessionHelpers.handle_toggle_star(%{"note-id" => note.id}, socket, load_fn)

      {:ok, toggled} = Notes.get_note(note.id)
      assert toggled.starred == true
    end

    test "accepts note_id from value key" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      note = create_note(session.id)
      socket = build_socket(%{})

      load_fn = fn s -> s end

      {:noreply, _result} =
        DmSessionHelpers.handle_toggle_star(%{"value" => note.id}, socket, load_fn)

      {:ok, toggled} = Notes.get_note(note.id)
      assert toggled.starred == true
    end

    test "toggles star from false to true" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      note = create_note(session.id)
      assert note.starred == false

      socket = build_socket(%{})
      load_fn = fn s -> s end

      DmSessionHelpers.handle_toggle_star(%{"note_id" => note.id}, socket, load_fn)

      {:ok, toggled} = Notes.get_note(note.id)
      assert toggled.starred == true
    end

    test "toggles star from true back to false" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      note = create_note(session.id)
      {:ok, starred_note} = Notes.update_note(note, %{starred: true, body: note.body})

      socket = build_socket(%{})
      load_fn = fn s -> s end

      DmSessionHelpers.handle_toggle_star(%{"note_id" => starred_note.id}, socket, load_fn)

      {:ok, unstarred} = Notes.get_note(starred_note.id)
      assert unstarred.starred == false
    end

    test "puts error flash when note_id does not exist" do
      socket = build_socket(%{})
      load_fn = fn s -> s end

      {:noreply, result} =
        DmSessionHelpers.handle_toggle_star(%{"note_id" => -1}, socket, load_fn)

      assert result.assigns.flash["error"] =~ "star"
    end
  end

  describe "handle_kill_session/1" do
    test "sets processing to false on socket" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      socket = build_socket(%{session_id: session.id, processing: true})

      {:noreply, result} = DmSessionHelpers.handle_kill_session(socket)

      assert result.assigns.processing == false
    end

    test "sets session to idle in the database when no worker is running" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent, %{status: "working"})
      socket = build_socket(%{session_id: session.id, processing: true})

      DmSessionHelpers.handle_kill_session(socket)

      {:ok, reloaded} = Sessions.get_session(session.id)
      assert reloaded.status == "idle"
    end

    test "does not crash when no worker is registered for the session" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      socket = build_socket(%{session_id: session.id, processing: false})

      # This should not raise even though no worker process is running
      assert {:noreply, _} = DmSessionHelpers.handle_kill_session(socket)
    end
  end
end
