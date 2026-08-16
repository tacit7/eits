defmodule EyeInTheSkyWeb.Components.DmPage.SettingsTabTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmPage.SettingsTab

  defp base_session_state do
    %{
      model: nil,
      effort: nil,
      max_budget_usd: nil,
      show_live_stream: true,
      thinking_enabled: false
    }
  end

  defp base_effective do
    %{
      "general" => %{
        "max_budget_usd" => nil,
        "show_live_stream" => true,
        "thinking_enabled" => false,
        "notify_on_stop" => false
      },
      "anthropic" => %{
        "permission_mode" => "acceptEdits",
        "max_turns" => nil,
        "fallback_model" => nil,
        "from_pr" => nil
      },
      "openai" => %{
        "ask_for_approval" => "never",
        "sandbox" => "workspace-write",
        "full_auto" => false,
        "dangerously_bypass_approvals_and_sandbox" => true
      }
    }
  end

  defp render_settings(overrides \\ []) do
    defaults = [
      scope: "session",
      subtab: "general",
      session: %{provider: "claude"},
      agent: nil,
      session_state: base_session_state(),
      notify_on_stop: false,
      overrides: [],
      effective: base_effective(),
      agent_effective: base_effective()
    ]

    render_component(&SettingsTab.settings_tab/1, Keyword.merge(defaults, overrides))
  end

  describe "settings_tab/1 — scope toggle" do
    test "renders scope toggle with session and agent buttons" do
      html = render_settings()
      assert html =~ "Saving to"
      assert html =~ "This session"
      assert html =~ "Agent default"
    end

    test "agent scope button has stable DOM id" do
      html = render_settings()
      assert html =~ ~s(id="dm-scope-agent")
    end

    test "session scope button has stable DOM id" do
      html = render_settings()
      assert html =~ ~s(id="dm-scope-session")
    end

    test "agent scope button is disabled when no agent record" do
      html = render_settings(agent: nil)
      assert html =~ ~s(id="dm-scope-agent")
      assert html =~ "disabled"
    end

    test "agent scope button is enabled when agent record is present" do
      html = render_settings(agent: %{id: 1, settings: %{}})
      assert html =~ ~s(id="dm-scope-agent")
      refute html =~ "disabled"
    end
  end

  describe "settings_tab/1 — subtab navigation" do
    test "renders tab navigation buttons" do
      html = render_settings()
      assert html =~ ~s(id="dm-subtab-general")
      assert html =~ "General"
      assert html =~ "Claude flags"
    end

    test "subtab buttons have stable DOM ids" do
      html = render_settings(session: %{provider: "claude"})
      assert html =~ ~s(id="dm-subtab-general")
      assert html =~ ~s(id="dm-subtab-anthropic")
    end

    test "claude provider shows Claude flags tab but not Codex flags" do
      html = render_settings(session: %{provider: "claude"})
      assert html =~ "Claude flags"
      refute html =~ "Codex flags"
    end

    test "codex provider shows Codex flags tab but not Claude flags" do
      html = render_settings(session: %{provider: "codex"})
      assert html =~ "Codex flags"
      refute html =~ "Claude flags"
    end

    test "pi provider shows neither Claude flags nor Codex flags" do
      html = render_settings(session: %{provider: "pi"})
      refute html =~ "Claude flags"
      refute html =~ "Codex flags"
    end
  end

  describe "settings_tab/1 — general subtab" do
    test "renders general subtab by default" do
      html = render_settings()
      assert html =~ "Model"
      assert html =~ "Display"
      assert html =~ "Notifications"
    end

    test "renders model display from session state" do
      html = render_settings(session_state: Map.merge(base_session_state(), %{model: "opus"}))
      assert html =~ "opus"
    end

    test "renders max_budget_usd from scoped effective settings" do
      eff = put_in(base_effective(), ["general", "max_budget_usd"], 10.5)
      html = render_settings(effective: eff, agent_effective: eff)
      assert html =~ "10.5"
    end

    test "renders notify on stop toggle" do
      html = render_settings(notify_on_stop: true)
      assert html =~ "Notify on stop"
    end

    test "renders live stream toggle with stable id" do
      html = render_settings()
      assert html =~ "Live stream"
      assert html =~ "general.show_live_stream"
    end

    test "renders thinking toggle" do
      html = render_settings()
      assert html =~ "Thinking"
      assert html =~ "thinking_enabled"
    end

    test "does not render effort row for claude provider" do
      html = render_settings(session: %{provider: "claude"})
      refute html =~ "Effort"
    end

    test "renders effort row for codex provider" do
      html =
        render_settings(
          session: %{provider: "codex"},
          session_state: Map.merge(base_session_state(), %{effort: "medium"})
        )

      assert html =~ "Effort"
      assert html =~ "medium"
    end

    test "renders override indicator when overrides present" do
      html = render_settings(overrides: ["model", "show_live_stream"])
      assert html =~ "bg-warning"
    end
  end

  describe "settings_tab/1 — anthropic subtab" do
    test "renders anthropic subtab for claude provider" do
      html = render_settings(subtab: "anthropic", session: %{provider: "claude"})
      assert html =~ "Claude flags"
      assert html =~ "Execution"
    end

    test "falls back to general when anthropic selected but provider is codex" do
      html =
        render_settings(subtab: "anthropic", session: %{provider: "codex"})

      assert html =~ "Model"
    end

    test "renders permission mode select with stable id" do
      html = render_settings(subtab: "anthropic", session: %{provider: "claude"})
      assert html =~ "Permission mode"
      assert html =~ "acceptEdits"
      assert html =~ "anthropic.permission_mode"
    end

    test "agent scope shows agent_effective values, not merged effective" do
      session_effective =
        put_in(base_effective(), ["anthropic", "permission_mode"], "bypassPermissions")

      agent_effective = put_in(base_effective(), ["anthropic", "permission_mode"], "plan")

      html =
        render_settings(
          scope: "agent",
          subtab: "anthropic",
          session: %{provider: "claude"},
          effective: session_effective,
          agent_effective: agent_effective
        )

      assert html =~ ~s(value="plan")
      refute html =~ ~s(value="bypassPermissions" selected)
    end

    test "session scope shows merged effective values" do
      session_effective =
        put_in(base_effective(), ["anthropic", "permission_mode"], "bypassPermissions")

      agent_effective = put_in(base_effective(), ["anthropic", "permission_mode"], "plan")

      html =
        render_settings(
          scope: "session",
          subtab: "anthropic",
          session: %{provider: "claude"},
          effective: session_effective,
          agent_effective: agent_effective
        )

      assert html =~ ~s(value="bypassPermissions")
    end

    test "from_pr row is visible at session scope" do
      html =
        render_settings(scope: "session", subtab: "anthropic", session: %{provider: "claude"})

      assert html =~ "from_pr"
    end

    test "from_pr row is hidden at agent scope" do
      html =
        render_settings(scope: "agent", subtab: "anthropic", session: %{provider: "claude"})

      refute html =~ "from_pr"
    end

    test "max_turns input uses step=1 and min=1 (positive integer constraint)" do
      html =
        render_settings(subtab: "anthropic", session: %{provider: "claude"})

      # The max_turns num_input must appear with integer constraints
      assert html =~ ~s(phx-value-key="anthropic.max_turns")
      assert html =~ ~s(step="1")
      assert html =~ ~s(min="1")
    end
  end

  describe "settings_tab/1 — openai subtab" do
    test "renders openai subtab for codex provider" do
      html = render_settings(subtab: "openai", session: %{provider: "codex"})
      assert html =~ "Codex flags"
      assert html =~ "Ask for approval"
    end

    test "renders sandbox select" do
      html = render_settings(subtab: "openai", session: %{provider: "codex"})
      assert html =~ "Sandbox"
      assert html =~ "workspace-write"
    end

    test "agent scope shows agent_effective for codex settings" do
      session_effective =
        put_in(base_effective(), ["openai", "ask_for_approval"], "on-failure")

      agent_effective = put_in(base_effective(), ["openai", "ask_for_approval"], "untrusted")

      html =
        render_settings(
          scope: "agent",
          subtab: "openai",
          session: %{provider: "codex"},
          effective: session_effective,
          agent_effective: agent_effective
        )

      assert html =~ ~s(value="untrusted")
      refute html =~ ~s(value="on-failure" selected)
    end
  end

  describe "settings_tab/1 — invalid subtab fallback" do
    test "unknown subtab falls back to general section" do
      html = render_settings(subtab: "invalid_subtab")
      assert html =~ "Model"
      assert html =~ "Display"

      document = LazyHTML.from_fragment(html)

      assert LazyHTML.attribute(
               LazyHTML.query(document, "#dm-subtab-general"),
               "class"
             ) == ["tab tab-active"]
    end

    test "nil subtab falls back to general section" do
      html = render_settings(subtab: nil)
      assert html =~ "Model"
    end

    test "anthropic subtab with pi provider falls back to general" do
      html = render_settings(subtab: "anthropic", session: %{provider: "pi"})
      assert html =~ "Model"
      refute html =~ "Permission mode"
    end

    test "openai subtab with claude provider falls back to general" do
      html = render_settings(subtab: "openai", session: %{provider: "claude"})
      assert html =~ "Model"
      refute html =~ "Ask for approval"
    end

    test "openai subtab with pi provider falls back to general" do
      html = render_settings(subtab: "openai", session: %{provider: "pi"})
      assert html =~ "Model"
      refute html =~ "Ask for approval"
    end
  end

  describe "settings_tab/1 — reset button" do
    test "renders reset button with correct scope label" do
      html = render_settings(scope: "agent")
      assert html =~ "Reset Agent settings"
      assert html =~ "reset_dm_settings"
    end

    test "reset button has stable DOM id" do
      html = render_settings()
      assert html =~ ~s(id="dm-settings-reset")
    end
  end

  describe "settings_tab/1 — layout" do
    test "renders section title with uppercase styling" do
      html = render_settings()
      assert html =~ "uppercase"
      assert html =~ "tracking-wide"
    end
  end
end
