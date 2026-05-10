defmodule EyeInTheSkyWeb.Components.DmPage.SettingsTabTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmPage.SettingsTab

  describe "settings_tab/1" do
    test "renders scope toggle with session and agent buttons" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: %{},
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "Saving to"
      assert html =~ "This session"
      assert html =~ "Agent default"
    end

    test "renders general subtab by default" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: %{},
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "Model"
      assert html =~ "Display"
      assert html =~ "Notifications"
    end

    test "renders anthropic subtab for claude provider" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "anthropic",
          session: %{provider: "claude"},
          agent: nil,
          session_state: %{},
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "Claude flags"
      assert html =~ "Execution"
    end

    test "renders openai subtab for codex provider" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "openai",
          session: %{provider: "codex"},
          agent: nil,
          session_state: %{},
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "Codex flags"
      assert html =~ "Ask for approval"
    end

    test "falls back to general when anthropic selected but provider is codex" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "anthropic",
          session: %{provider: "codex"},
          agent: nil,
          session_state: %{},
          notify_on_stop: false,
          overrides: []
        )

      # Should render general section since provider doesn't support anthropic
      assert html =~ "Model"
    end

    test "renders model section with session state" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: %{model: "opus", effort: "high", max_budget_usd: 10.5},
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "opus"
      assert html =~ "10.5"
    end

    test "renders notify on stop toggle when enabled" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: %{},
          notify_on_stop: true,
          overrides: []
        )

      assert html =~ "Notify on stop"
      assert html =~ "notify_on_stop"
    end

    test "renders settings with override indicator" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: %{},
          notify_on_stop: false,
          overrides: ["model", "show_live_stream"]
        )

      # Override indicators should be present
      assert html =~ "bg-warning"
    end

    test "renders live stream toggle" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: %{show_live_stream: true},
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "Live stream"
      assert html =~ "show_live_stream"
    end

    test "renders thinking toggle" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: %{thinking_enabled: true},
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "Thinking"
      assert html =~ "thinking_enabled"
    end

    test "renders effort section only for codex provider" do
      html_claude =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: %{},
          notify_on_stop: false,
          overrides: []
        )

      # Claude provider should not show effort
      refute html_claude =~ "Effort"

      html_codex =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "codex"},
          agent: nil,
          session_state: %{effort: "medium"},
          notify_on_stop: false,
          overrides: []
        )

      # Codex provider should show effort
      assert html_codex =~ "Effort"
    end

    test "renders reset button with correct scope" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "agent",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: %{},
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "Reset Agent settings"
      assert html =~ "reset_dm_settings"
    end

    test "renders tab navigation" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: %{},
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "General"
      assert html =~ "Claude flags"
    end

    test "renders permission mode select in anthropic section" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "anthropic",
          session: %{provider: "claude"},
          agent: nil,
          session_state: %{},
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "Permission mode"
      assert html =~ "acceptEdits"
      assert html =~ "permission_mode"
    end

    test "renders sandbox select in openai section" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "openai",
          session: %{provider: "codex"},
          agent: nil,
          session_state: %{},
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "Sandbox"
      assert html =~ "workspace-write"
    end

    test "renders section with title styling" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: %{},
          notify_on_stop: false,
          overrides: []
        )

      # Check for section title styling
      assert html =~ "uppercase"
      assert html =~ "tracking-wide"
    end
  end
end
