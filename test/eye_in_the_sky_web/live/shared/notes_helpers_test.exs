defmodule EyeInTheSkyWeb.Live.Shared.NotesHelpersTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.Notes
  alias EyeInTheSkyWeb.Live.Shared.NotesHelpers

  # Build a minimal socket with assigns relevant to NotesHelpers.
  # Phoenix.Component.assign/3 and Phoenix.LiveView.put_flash/3 require
  # a real %Phoenix.LiveView.Socket{} with the standard nested fields.
  defp socket(assigns \\ %{}) do
    base_assigns = %{
      search_query: "",
      sort_by: "newest",
      type_filter: "all",
      starred_filter: false,
      flash: %{},
      __changed__: %{}
    }

    %Phoenix.LiveView.Socket{
      assigns: Map.merge(base_assigns, assigns),
      private: %{root_view: __MODULE__, connect_info: %{}, live_temp: %{}},
      transport_pid: nil
    }
  end

  defp create_note(overrides \\ %{}) do
    defaults = %{
      parent_type: "project",
      parent_id: "1",
      body: "test body #{System.unique_integer([:positive])}",
      title: "Test note #{System.unique_integer([:positive])}"
    }

    {:ok, note} = Notes.create_note(Map.merge(defaults, overrides))
    note
  end

  # A no-op reload_fn for tests that only check assign mutations.
  defp noop_reload(socket), do: socket

  # ---------------------------------------------------------------------------
  # handle_search/3
  # ---------------------------------------------------------------------------

  describe "handle_search/3" do
    test "assigns the search_query from params and calls reload_fn" do
      socket = socket()
      reload_called = :ets.new(:test_reload_search, [:set, :public])
      :ets.insert(reload_called, {:called, false})

      reload_fn = fn s ->
        :ets.insert(reload_called, {:called, true})
        s
      end

      {:noreply, result} = NotesHelpers.handle_search(%{"query" => "elixir"}, socket, reload_fn)
      assert result.assigns.search_query == "elixir"
      assert :ets.lookup(reload_called, :called) == [{:called, true}]
    end

    test "assigns empty string clears the query" do
      socket = socket(%{search_query: "previous"})
      {:noreply, result} = NotesHelpers.handle_search(%{"query" => ""}, socket, &noop_reload/1)
      assert result.assigns.search_query == ""
    end
  end

  # ---------------------------------------------------------------------------
  # handle_sort_notes/3
  # ---------------------------------------------------------------------------

  describe "handle_sort_notes/3" do
    test "assigns the sort_by value from params" do
      socket = socket(%{sort_by: "newest"})
      {:noreply, result} = NotesHelpers.handle_sort_notes(%{"by" => "oldest"}, socket, &noop_reload/1)
      assert result.assigns.sort_by == "oldest"
    end

    test "calls reload_fn after assigning sort" do
      counter = :ets.new(:test_sort_counter, [:set, :public])
      :ets.insert(counter, {:n, 0})

      reload_fn = fn s ->
        [{:n, n}] = :ets.lookup(counter, :n)
        :ets.insert(counter, {:n, n + 1})
        s
      end

      {:noreply, _} = NotesHelpers.handle_sort_notes(%{"by" => "newest"}, socket(), reload_fn)
      assert :ets.lookup(counter, :n) == [{:n, 1}]
    end
  end

  # ---------------------------------------------------------------------------
  # handle_filter_type/3
  # ---------------------------------------------------------------------------

  describe "handle_filter_type/3" do
    test "assigns the type_filter from params" do
      socket = socket(%{type_filter: "all"})
      {:noreply, result} = NotesHelpers.handle_filter_type(%{"type" => "session"}, socket, &noop_reload/1)
      assert result.assigns.type_filter == "session"
    end

    test "accepts any string value for type_filter" do
      {:noreply, result} = NotesHelpers.handle_filter_type(%{"type" => "task"}, socket(), &noop_reload/1)
      assert result.assigns.type_filter == "task"
    end
  end

  # ---------------------------------------------------------------------------
  # handle_toggle_starred_filter/3
  # ---------------------------------------------------------------------------

  describe "handle_toggle_starred_filter/3" do
    test "flips starred_filter from false to true" do
      socket = socket(%{starred_filter: false})
      {:noreply, result} = NotesHelpers.handle_toggle_starred_filter(%{}, socket, &noop_reload/1)
      assert result.assigns.starred_filter == true
    end

    test "flips starred_filter from true to false" do
      socket = socket(%{starred_filter: true})
      {:noreply, result} = NotesHelpers.handle_toggle_starred_filter(%{}, socket, &noop_reload/1)
      assert result.assigns.starred_filter == false
    end

    test "calls reload_fn after toggling" do
      counter = :ets.new(:test_toggle_counter, [:set, :public])
      :ets.insert(counter, {:n, 0})

      reload_fn = fn s ->
        [{:n, n}] = :ets.lookup(counter, :n)
        :ets.insert(counter, {:n, n + 1})
        s
      end

      {:noreply, _} = NotesHelpers.handle_toggle_starred_filter(%{}, socket(%{starred_filter: false}), reload_fn)
      assert :ets.lookup(counter, :n) == [{:n, 1}]
    end
  end

  # ---------------------------------------------------------------------------
  # handle_toggle_star/3
  # ---------------------------------------------------------------------------

  describe "handle_toggle_star/3" do
    test "toggles starred to true via note_id key and calls reload_fn" do
      note = create_note(%{starred: false})
      reload_called = :ets.new(:test_toggle_star, [:set, :public])
      :ets.insert(reload_called, {:called, false})

      reload_fn = fn s ->
        :ets.insert(reload_called, {:called, true})
        s
      end

      {:noreply, _result} =
        NotesHelpers.handle_toggle_star(%{"note_id" => note.id}, socket(), reload_fn)

      assert :ets.lookup(reload_called, :called) == [{:called, true}]
      {:ok, updated} = Notes.get_note(note.id)
      assert updated.starred == true
    end

    test "accepts note-id (hyphenated) key" do
      note = create_note(%{starred: false})
      {:noreply, _result} =
        NotesHelpers.handle_toggle_star(%{"note-id" => note.id}, socket(), &noop_reload/1)

      {:ok, updated} = Notes.get_note(note.id)
      assert updated.starred == true
    end

    test "accepts value key" do
      note = create_note(%{starred: true})
      {:noreply, _result} =
        NotesHelpers.handle_toggle_star(%{"value" => note.id}, socket(), &noop_reload/1)

      {:ok, updated} = Notes.get_note(note.id)
      assert updated.starred == false
    end

    test "puts flash error when note_id does not exist" do
      # Non-existent ID (a string that won't match any row).
      # toggle_starred returns {:error, :not_found} for empty result sets.
      {:noreply, result} =
        NotesHelpers.handle_toggle_star(%{"note_id" => 0}, socket(), &noop_reload/1)

      assert result.assigns.flash["error"] == "Failed to toggle star"
    end
  end

  # ---------------------------------------------------------------------------
  # handle_delete_note/3
  # ---------------------------------------------------------------------------

  describe "handle_delete_note/3" do
    test "deletes the note and calls reload_fn via note_id key" do
      note = create_note()
      reload_called = :ets.new(:test_delete_note, [:set, :public])
      :ets.insert(reload_called, {:called, false})

      reload_fn = fn s ->
        :ets.insert(reload_called, {:called, true})
        s
      end

      {:noreply, _result} =
        NotesHelpers.handle_delete_note(%{"note_id" => note.id}, socket(), reload_fn)

      assert :ets.lookup(reload_called, :called) == [{:called, true}]
      assert Notes.get_note(note.id) == {:error, :not_found}
    end

    test "accepts note-id (hyphenated) key" do
      note = create_note()
      {:noreply, _} =
        NotesHelpers.handle_delete_note(%{"note-id" => note.id}, socket(), &noop_reload/1)

      assert Notes.get_note(note.id) == {:error, :not_found}
    end

    test "accepts value key" do
      note = create_note()
      {:noreply, _} =
        NotesHelpers.handle_delete_note(%{"value" => note.id}, socket(), &noop_reload/1)

      assert Notes.get_note(note.id) == {:error, :not_found}
    end

    test "accepts item_id key" do
      note = create_note()
      {:noreply, _} =
        NotesHelpers.handle_delete_note(%{"item_id" => note.id}, socket(), &noop_reload/1)

      assert Notes.get_note(note.id) == {:error, :not_found}
    end

    test "puts flash error when note not found" do
      {:noreply, result} =
        NotesHelpers.handle_delete_note(%{"note_id" => 0}, socket(), &noop_reload/1)

      assert result.assigns.flash["error"] == "Note not found"
    end
  end
end
