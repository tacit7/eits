defmodule EyeInTheSkyWeb.OverviewLive.Settings.SystemTabTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.OverviewLive.Settings.SystemTab

  defp db_info(opts \\ []) do
    %{
      path: Keyword.get(opts, :path, "/path/to/eits.db"),
      size: Keyword.get(opts, :size, 1024),
      table_counts: Keyword.get(opts, :table_counts, %{})
    }
  end

  defp render_tab(settings \\ %{}, db \\ db_info()) do
    render_component(&SystemTab.render/1, %{settings: settings, db_info: db})
  end

  describe "render/1 - structure" do
    test "renders System heading" do
      html = render_tab()
      assert html =~ "System"
    end

    test "renders card with divide-y layout" do
      html = render_tab()
      assert html =~ "card"
      assert html =~ "divide-y"
    end
  end

  describe "render/1 - toggles" do
    test "renders Log Raw Claude Output toggle" do
      html = render_tab(%{"log_claude_raw" => "false"})
      assert html =~ "Log Raw Claude Output"
      assert html =~ "Log raw JSONL output from Claude CLI"
      assert html =~ ~s(phx-click="toggle_setting")
      assert html =~ ~s(phx-value-key="log_claude_raw")
    end

    test "log_claude_raw toggle is checked when value is 'true'" do
      html = render_tab(%{"log_claude_raw" => "true"})
      # The checked attribute should appear on the claude raw input
      assert html =~ "log_claude_raw"
      assert html =~ "checked"
    end

    test "log_claude_raw toggle is not checked when value is 'false'" do
      html = render_tab(%{"log_claude_raw" => "false"})
      # The checked attribute should NOT appear on the claude raw checkbox
      # (Phoenix renders checked only when condition is true)
      refute html =~ ~s(phx-value-key="log_claude_raw" checked)
    end

    test "renders Log Raw Codex Output toggle" do
      html = render_tab(%{"log_codex_raw" => "false"})
      assert html =~ "Log Raw Codex Output"
      assert html =~ "Log raw output from Codex CLI"
      assert html =~ ~s(phx-value-key="log_codex_raw")
    end

    test "renders Per-session Rate-Limit Bucket toggle" do
      html = render_tab(%{"rate_limit_per_session" => "false"})
      assert html =~ "Per-session Rate-Limit Bucket"
      assert html =~ ~s(phx-value-key="rate_limit_per_session")
    end

    test "rate limit toggle mentions Phase 2 context" do
      html = render_tab()
      assert html =~ "Phase 2"
      assert html =~ "IP-keyed bucket"
    end

    test "all toggles use daisyui toggle class" do
      html = render_tab()
      assert html =~ "toggle toggle-sm toggle-primary"
    end

    test "all three toggle settings appear in output" do
      html = render_tab(%{
        "log_claude_raw" => "true",
        "log_codex_raw" => "false",
        "rate_limit_per_session" => "true"
      })

      assert html =~ "log_claude_raw"
      assert html =~ "log_codex_raw"
      assert html =~ "rate_limit_per_session"
    end
  end

  describe "render/1 - database info" do
    test "renders Database section heading" do
      html = render_tab()
      assert html =~ "Database"
    end

    test "renders Path label and value" do
      html = render_tab(%{}, db_info(path: "/var/lib/eits.db"))
      assert html =~ "Path"
      assert html =~ "/var/lib/eits.db"
    end

    test "renders Size label" do
      html = render_tab()
      assert html =~ "Size"
    end

    test "renders Table Counts section" do
      html = render_tab(%{}, db_info(table_counts: %{"sessions" => 42, "tasks" => 7}))
      assert html =~ "Table Counts"
      assert html =~ "sessions"
      assert html =~ "42"
      assert html =~ "tasks"
      assert html =~ "7"
    end

    test "handles empty table_counts without crashing" do
      html = render_tab(%{}, db_info(table_counts: %{}))
      assert is_binary(html)
      assert html =~ "Table Counts"
    end

    test "renders grid layout for path and size" do
      html = render_tab()
      assert html =~ "grid grid-cols-2"
    end

    test "renders database size through format_db_size helper" do
      html = render_tab(%{}, db_info(size: 2_097_152))
      # format_db_size is called on the size value; just verify section renders
      assert html =~ "Size"
      assert is_binary(html)
    end
  end

  describe "render/1 - edge cases" do
    test "renders with all settings empty" do
      html = render_tab(%{})
      assert is_binary(html)
      assert String.length(html) > 0
    end
  end
end
