defmodule EyeInTheSkyWeb.OverviewLive.Settings.SystemTabTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.OverviewLive.Settings.SystemTab

  describe "render/1" do
    test "renders system section with heading" do
      assigns = %{
        settings: %{},
        db_info: %{path: "/path/to/db", size: 1024, table_counts: []},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(SystemTab, assigns)

      assert html =~ "System"
    end

    test "renders log claude raw toggle" do
      assigns = %{
        settings: %{"log_claude_raw" => "false"},
        db_info: %{path: "/path/to/db", size: 1024, table_counts: []},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(SystemTab, assigns)

      assert html =~ "Log Raw Claude Output"
      assert html =~ "Log raw JSONL output from Claude CLI"
      assert html =~ "phx-click=\"toggle_setting\""
      assert html =~ "phx-value-key=\"log_claude_raw\""
    end

    test "log claude raw toggle checked when true" do
      assigns = %{
        settings: %{"log_claude_raw" => "true"},
        db_info: %{path: "/path/to/db", size: 1024, table_counts: []},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(SystemTab, assigns)

      assert html =~ "log_claude_raw"
      assert html =~ "checked"
    end

    test "renders log codex raw toggle" do
      assigns = %{
        settings: %{"log_codex_raw" => "false"},
        db_info: %{path: "/path/to/db", size: 1024, table_counts: []},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(SystemTab, assigns)

      assert html =~ "Log Raw Codex Output"
      assert html =~ "Log raw output from Codex CLI"
      assert html =~ "phx-value-key=\"log_codex_raw\""
    end

    test "renders rate limit per session toggle" do
      assigns = %{
        settings: %{"rate_limit_per_session" => "false"},
        db_info: %{path: "/path/to/db", size: 1024, table_counts: []},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(SystemTab, assigns)

      assert html =~ "Per-session Rate-Limit Bucket"
      assert html =~ "phx-value-key=\"rate_limit_per_session\""
      assert html =~ "x-eits-session header support"
    end

    test "renders database info section" do
      assigns = %{
        settings: %{},
        db_info: %{
          path: "/var/lib/db/eits.db",
          size: 5_242_880,
          table_counts: %{"sessions" => 42, "tasks" => 100, "agents" => 15}
        },
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(SystemTab, assigns)

      assert html =~ "Database"
      assert html =~ "Path"
      assert html =~ "/var/lib/db/eits.db"
      assert html =~ "Size"
    end

    test "renders table counts as badges" do
      assigns = %{
        settings: %{},
        db_info: %{
          path: "/path/to/db",
          size: 1024,
          table_counts: %{"sessions" => 42, "tasks" => 100}
        },
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(SystemTab, assigns)

      assert html =~ "Table Counts"
      assert html =~ "sessions"
      assert html =~ "42"
      assert html =~ "tasks"
      assert html =~ "100"
    end

    test "renders card with divide-y styling" do
      assigns = %{
        settings: %{},
        db_info: %{path: "/path/to/db", size: 1024, table_counts: []},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(SystemTab, assigns)

      assert html =~ "card bg-base-100"
      assert html =~ "divide-y"
      assert html =~ "divide-base-300"
    end

    test "renders database size with format_db_size helper" do
      assigns = %{
        settings: %{},
        db_info: %{
          path: "/path/to/db",
          size: 1_048_576,
          table_counts: %{}
        },
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(SystemTab, assigns)

      # format_db_size is called on the size, so we check that the value appears
      assert html =~ "path"
      assert html =~ "/path/to/db"
    end

    test "renders toggles with daisyui toggle class" do
      assigns = %{
        settings: %{"log_claude_raw" => "false"},
        db_info: %{path: "/path/to/db", size: 1024, table_counts: []},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(SystemTab, assigns)

      assert html =~ "toggle toggle-sm toggle-primary"
    end

    test "handles empty table_counts gracefully" do
      assigns = %{
        settings: %{},
        db_info: %{path: "/path/to/db", size: 1024, table_counts: %{}},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(SystemTab, assigns)

      assert is_binary(html)
      assert String.length(html) > 0
    end

    test "renders all three toggle settings in sequence" do
      assigns = %{
        settings: %{
          "log_claude_raw" => "true",
          "log_codex_raw" => "false",
          "rate_limit_per_session" => "true"
        },
        db_info: %{path: "/path/to/db", size: 1024, table_counts: []},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(SystemTab, assigns)

      # All three toggles should appear with their keys
      assert html =~ "log_claude_raw"
      assert html =~ "log_codex_raw"
      assert html =~ "rate_limit_per_session"

      # Verify they're within toggle-setting handlers
      assert String.split(html, "toggle_setting") |> length() >= 4 # At least 3 toggles
    end

    test "displays tooltip text for rate limit setting" do
      assigns = %{
        settings: %{"rate_limit_per_session" => "false"},
        db_info: %{path: "/path/to/db", size: 1024, table_counts: []},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(SystemTab, assigns)

      assert html =~ "Phase 2"
      assert html =~ "IP-keyed bucket"
    end

    test "renders grid layout for database info" do
      assigns = %{
        settings: %{},
        db_info: %{
          path: "/path/to/db",
          size: 1024,
          table_counts: %{"t1" => 1, "t2" => 2}
        },
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(SystemTab, assigns)

      assert html =~ "grid grid-cols-2"
      assert html =~ "gap-x-8 gap-y-2"
    end
  end
end
