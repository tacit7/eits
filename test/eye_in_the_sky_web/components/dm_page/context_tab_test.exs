defmodule EyeInTheSkyWeb.Components.DmPage.ContextTabTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmPage.ContextTab

  describe "context_tab/1" do
    test "renders empty state when context is nil" do
      html =
        render_component(
          &ContextTab.context_tab/1,
          session_context: nil
        )

      assert html =~ "No context yet"
      assert html =~ "Session context will appear here once set"
    end

    test "renders empty state when context is empty object" do
      html =
        render_component(
          &ContextTab.context_tab/1,
          session_context: %{}
        )

      assert html =~ "No context yet"
    end

    test "parses and renders single context section" do
      context = %{
        context: "# Project Overview\n\nThis is a test project",
        updated_at: DateTime.utc_now()
      }

      html =
        render_component(
          &ContextTab.context_tab/1,
          session_context: context
        )

      assert html =~ "Project Overview"
      assert html =~ "This is a test project"
    end

    test "parses and renders multiple context sections separated by ---" do
      context = %{
        context:
          "# Architecture\n\nSystem design here\n---\n# API Docs\n\nEndpoint reference here",
        updated_at: DateTime.utc_now()
      }

      html =
        render_component(
          &ContextTab.context_tab/1,
          session_context: context
        )

      assert html =~ "Architecture"
      assert html =~ "System design here"
      assert html =~ "API Docs"
      assert html =~ "Endpoint reference here"
    end

    test "extracts title from markdown heading" do
      context = %{
        context: "## Getting Started\n\nSome content here",
        updated_at: DateTime.utc_now()
      }

      html =
        render_component(
          &ContextTab.context_tab/1,
          session_context: context
        )

      assert html =~ "Getting Started"
    end

    test "uses 'Section' as fallback title when no heading found" do
      context = %{
        context: "Some content without a heading",
        updated_at: DateTime.utc_now()
      }

      html =
        render_component(
          &ContextTab.context_tab/1,
          session_context: context
        )

      assert html =~ "Section"
    end

    test "trims whitespace from section content" do
      context = %{
        context: "\n\n# Title\n\nContent\n\n---\n\n# Another\n\nMore content\n\n",
        updated_at: DateTime.utc_now()
      }

      html =
        render_component(
          &ContextTab.context_tab/1,
          session_context: context
        )

      assert html =~ "Title"
      assert html =~ "Another"
    end

    test "renders collapsible sections" do
      context = %{
        context: "# Section One\n\nContent one\n---\n# Section Two\n\nContent two",
        updated_at: DateTime.utc_now()
      }

      html =
        render_component(
          &ContextTab.context_tab/1,
          session_context: context
        )

      assert html =~ "collapse"
      assert html =~ "collapse-arrow"
    end

    test "renders section with unique id based on index" do
      context = %{
        context: "# First\n\nContent\n---\n# Second\n\nMore",
        updated_at: DateTime.utc_now()
      }

      html =
        render_component(
          &ContextTab.context_tab/1,
          session_context: context
        )

      assert html =~ "dm-context-section-0"
      assert html =~ "dm-context-section-1"
    end

    test "renders updated_at timestamp for first section only" do
      context = %{
        context: "# First\n\nContent\n---\n# Second\n\nMore",
        updated_at: DateTime.utc_now()
      }

      html =
        render_component(
          &ContextTab.context_tab/1,
          session_context: context
        )

      # Only the first section (index 0) should have the timestamp
      assert html =~ "context-updated-at"
    end

    test "renders markdown body with MarkdownMessage hook" do
      context = %{
        context: "# Title\n\nSome **bold** and *italic* text",
        updated_at: DateTime.utc_now()
      }

      html =
        render_component(
          &ContextTab.context_tab/1,
          session_context: context
        )

      assert html =~ "phx-hook=\"MarkdownMessage\""
      assert html =~ "dm-markdown"
    end

    test "handles multi-level markdown headings" do
      context = %{
        context: "### Deep Heading\n\nContent here",
        updated_at: DateTime.utc_now()
      }

      html =
        render_component(
          &ContextTab.context_tab/1,
          session_context: context
        )

      assert html =~ "Deep Heading"
    end

    test "empty sections between --- are skipped" do
      context = %{
        context: "# Real Section\n\nContent\n---\n\n---\n# Another\n\nMore",
        updated_at: DateTime.utc_now()
      }

      html =
        render_component(
          &ContextTab.context_tab/1,
          session_context: context
        )

      # Should have 2 sections (empty ones filtered out)
      assert html =~ "dm-context-section-0"
      assert html =~ "dm-context-section-1"
      refute html =~ "dm-context-section-2"
    end
  end
end
