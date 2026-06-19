defmodule EyeInTheSkyWeb.Components.DmPage.SettingsTabTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmPage.SettingsTab

  # The general_section accesses @session_state.model, @session_state.effort,
  # @session_state.max_budget_usd, @session_state[:show_live_stream], and
  # @session_state.thinking_enabled via direct map access — all must be present.
  defp base_session_state do
    %{
      model: nil,
      effort: nil,
      max_budget_usd: nil,
      show_live_stream: true,
      thinking_enabled: false
    }
  end

  describe "settings_tab/1" do
    test "renders scope toggle with session and agent buttons" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: base_session_state(),
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
          session_state: base_session_state(),
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
          session_state: base_session_state(),
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
          session_state: base_session_state(),
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
          session_state: base_session_state(),
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "Model"
    end

    test "renders model section with session state values" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: Map.merge(base_session_state(), %{model: "opus", max_budget_usd: 10.5}),
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "opus"
      assert html =~ "10.5"
    end

    test "renders notify on stop toggle" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: base_session_state(),
          notify_on_stop: true,
          overrides: []
        )

      assert html =~ "Notify on stop"
    end

    test "renders override indicator when overrides present" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: base_session_state(),
          notify_on_stop: false,
          overrides: ["model", "show_live_stream"]
        )

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
          session_state: base_session_state(),
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
          session_state: base_session_state(),
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "Thinking"
      assert html =~ "thinking_enabled"
    end

    test "does not render effort row for claude provider" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: base_session_state(),
          notify_on_stop: false,
          overrides: []
        )

      refute html =~ "Effort"
    end

    test "renders effort row for codex provider" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "codex"},
          agent: nil,
          session_state: Map.merge(base_session_state(), %{effort: "medium"}),
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "Effort"
      assert html =~ "medium"
    end

    test "renders reset button with correct scope label" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "agent",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: base_session_state(),
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "Reset Agent settings"
      assert html =~ "reset_dm_settings"
    end

    test "renders tab navigation buttons" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: base_session_state(),
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
          session_state: base_session_state(),
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "Permission mode"
      assert html =~ "acceptEdits"
    end

    test "renders sandbox select in openai section" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "openai",
          session: %{provider: "codex"},
          agent: nil,
          session_state: base_session_state(),
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "Sandbox"
      assert html =~ "workspace-write"
    end

    test "renders section title with uppercase styling" do
      html =
        render_component(
          &SettingsTab.settings_tab/1,
          scope: "session",
          subtab: "general",
          session: %{provider: "claude"},
          agent: nil,
          session_state: base_session_state(),
          notify_on_stop: false,
          overrides: []
        )

      assert html =~ "uppercase"
      assert html =~ "tracking-wide"
    end
  end
end
