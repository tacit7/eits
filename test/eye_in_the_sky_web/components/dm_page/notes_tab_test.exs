defmodule EyeInTheSkyWeb.Components.DmPage.NotesTabTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmPage.NotesTab

  describe "notes_tab/1" do
    test "renders empty state with create button when no notes" do
      html =
        render_component(
          &NotesTab.notes_tab/1,
          notes: []
        )

      assert html =~ "No notes yet"
      assert html =~ "Notes from this session will appear here"
      assert html =~ "Create Note"
    end

    test "renders notes list with create button" do
      notes = [
        %{
          id: 1,
          uuid: "uuid-1",
          title: "Setup Notes",
          body: "Initial project setup instructions",
          created_at: DateTime.utc_now(),
          starred: false
        }
      ]

      html =
        render_component(
          &NotesTab.notes_tab/1,
          notes: notes
        )

      assert html =~ "Setup Notes"
      assert html =~ "Initial project setup instructions"
      assert html =~ "Create Note"
    end

    test "renders note without title, using extracted body title" do
      notes = [
        %{
          id: 1,
          uuid: nil,
          title: nil,
          body: "# Extracted Title\n\nBody content",
          created_at: DateTime.utc_now(),
          starred: false
        }
      ]

      html =
        render_component(
          &NotesTab.notes_tab/1,
          notes: notes
        )

      assert html =~ "Extracted Title"
      assert html =~ "Body content"
    end

    test "renders note id truncated to 8 characters" do
      notes = [
        %{
          id: 1,
          uuid: "very-long-uuid-string-here",
          title: "Note",
          body: "Content",
          created_at: DateTime.utc_now(),
          starred: false
        }
      ]

      html =
        render_component(
          &NotesTab.notes_tab/1,
          notes: notes
        )

      assert html =~ "very-long"
      refute html =~ "very-long-uuid"
    end

    test "renders fallback to note id when uuid not present" do
      notes = [
        %{
          id: 123456789,
          uuid: nil,
          title: "Note",
          body: "Content",
          created_at: DateTime.utc_now(),
          starred: false
        }
      ]

      html =
        render_component(
          &NotesTab.notes_tab/1,
          notes: notes
        )

      assert html =~ "12345678"
    end

    test "renders starred notes with filled star icon" do
      notes = [
        %{
          id: 1,
          uuid: "uuid-1",
          title: "Important",
          body: "Content",
          created_at: DateTime.utc_now(),
          starred: true
        }
      ]

      html =
        render_component(
          &NotesTab.notes_tab/1,
          notes: notes
        )

      assert html =~ "hero-star-solid"
      assert html =~ "text-warning"
    end

    test "renders unstarred notes with outline star icon" do
      notes = [
        %{
          id: 1,
          uuid: "uuid-1",
          title: "Note",
          body: "Content",
          created_at: DateTime.utc_now(),
          starred: false
        }
      ]

      html =
        render_component(
          &NotesTab.notes_tab/1,
          notes: notes
        )

      assert html =~ "hero-star\""
      assert html =~ "text-base-content/15"
    end

    test "renders copy to clipboard button" do
      notes = [
        %{
          id: 1,
          uuid: "uuid-123",
          title: "Note",
          body: "Content",
          created_at: DateTime.utc_now(),
          starred: false
        }
      ]

      html =
        render_component(
          &NotesTab.notes_tab/1,
          notes: notes
        )

      assert html =~ "CopyToClipboard"
      assert html =~ "copy-note-1"
      assert html =~ "data-copy=\"uuid-123\""
    end

    test "renders note with markdown content hook" do
      notes = [
        %{
          id: 1,
          uuid: "uuid-1",
          title: "Note",
          body: "# Heading\n\nSome **bold** text",
          created_at: DateTime.utc_now(),
          starred: false
        }
      ]

      html =
        render_component(
          &NotesTab.notes_tab/1,
          notes: notes
        )

      assert html =~ "phx-hook=\"MarkdownMessage\""
      assert html =~ "dm-markdown"
      assert html =~ "data-raw-body"
    end

    test "renders collapsible note sections" do
      notes = [
        %{
          id: 1,
          uuid: "uuid-1",
          title: "Collapsible Note",
          body: "Content",
          created_at: DateTime.utc_now(),
          starred: false
        }
      ]

      html =
        render_component(
          &NotesTab.notes_tab/1,
          notes: notes
        )

      assert html =~ "collapse"
      assert html =~ "collapse-arrow"
    end

    test "renders note with unique id" do
      notes = [
        %{
          id: 42,
          uuid: "uuid-42",
          title: "Note",
          body: "Content",
          created_at: DateTime.utc_now(),
          starred: false
        }
      ]

      html =
        render_component(
          &NotesTab.notes_tab/1,
          notes: notes
        )

      assert html =~ "dm-note-42"
    end

    test "renders multiple notes" do
      notes = [
        %{
          id: 1,
          uuid: "uuid-1",
          title: "First Note",
          body: "First content",
          created_at: DateTime.utc_now(),
          starred: false
        },
        %{
          id: 2,
          uuid: "uuid-2",
          title: "Second Note",
          body: "Second content",
          created_at: DateTime.utc_now(),
          starred: true
        }
      ]

      html =
        render_component(
          &NotesTab.notes_tab/1,
          notes: notes
        )

      assert html =~ "First Note"
      assert html =~ "Second Note"
      assert html =~ "dm-note-1"
      assert html =~ "dm-note-2"
    end

    test "renders star toggle with correct phx-click" do
      notes = [
        %{
          id: 5,
          uuid: "uuid-5",
          title: "Note",
          body: "Content",
          created_at: DateTime.utc_now(),
          starred: false
        }
      ]

      html =
        render_component(
          &NotesTab.notes_tab/1,
          notes: notes
        )

      assert html =~ "toggle-note-star-5"
      assert html =~ "toggle_star"
    end
  end
end
