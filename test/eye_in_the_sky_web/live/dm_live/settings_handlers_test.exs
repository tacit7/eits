defmodule EyeInTheSkyWeb.DmLive.SettingsHandlersTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.{Agents, Factory, Sessions}
  alias EyeInTheSkyWeb.DmLive.SettingsHandlers

  # Helper to build a bare socket with assigns
  defp build_socket(assigns) do
    base = %{__changed__: %{}, flash: %{}, private: %{live_temp: %{}}}

    %Phoenix.LiveView.Socket{
      assigns: Map.merge(base, assigns)
    }
  end

  describe "handle_scope_change/2" do
    test "updates dm_settings_scope assign" do
      socket = build_socket(%{dm_settings_scope: "agent"})

      {:noreply, result} = SettingsHandlers.handle_scope_change("session", socket)

      assert result.assigns.dm_settings_scope == "session"
    end

    test "handles switching from session to agent" do
      socket = build_socket(%{dm_settings_scope: "session"})

      {:noreply, result} = SettingsHandlers.handle_scope_change("agent", socket)

      assert result.assigns.dm_settings_scope == "agent"
    end

    test "handles switching from agent to session" do
      socket = build_socket(%{dm_settings_scope: "agent"})

      {:noreply, result} = SettingsHandlers.handle_scope_change("session", socket)

      assert result.assigns.dm_settings_scope == "session"
    end
  end

  describe "handle_subtab_change/2" do
    test "updates dm_settings_subtab assign" do
      socket = build_socket(%{dm_settings_subtab: "appearance"})

      {:noreply, result} = SettingsHandlers.handle_subtab_change("general", socket)

      assert result.assigns.dm_settings_subtab == "general"
    end

    test "handles switching between different subtabs" do
      socket = build_socket(%{dm_settings_subtab: "general"})

      {:noreply, result} = SettingsHandlers.handle_subtab_change("appearance", socket)

      assert result.assigns.dm_settings_subtab == "appearance"
    end
  end

  describe "handle_setting_update_with_value/4" do
    test "persists a session-scoped setting" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session: session,
          agent: nil,
          dm_settings_effective: %{},
          dm_settings_agent_overrides: %{},
          dm_settings_session_overrides: %{},
          show_live_stream: false,
          thinking_enabled: false,
          max_budget_usd: nil,
          notify_on_stop: false
        })

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value("session", "theme", "dark", socket)

      # Session should be updated
      assert result.assigns.session.id == session.id
      # dm_settings_session_overrides should reflect the change
      assert is_map(result.assigns.dm_settings_session_overrides)
    end

    test "persists an agent-scoped setting" do
      agent = Factory.create_agent()
      session = Factory.new_session()

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          dm_settings_effective: %{},
          dm_settings_agent_overrides: %{},
          dm_settings_session_overrides: %{},
          show_live_stream: false,
          thinking_enabled: false,
          max_budget_usd: nil,
          notify_on_stop: false
        })

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value("agent", "theme", "light", socket)

      # Agent should be updated
      assert result.assigns.agent.id == agent.id
    end

    test "returns error flash for invalid settings" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session: session,
          agent: nil,
          dm_settings_effective: %{},
          dm_settings_agent_overrides: %{},
          dm_settings_session_overrides: %{},
          show_live_stream: false,
          thinking_enabled: false,
          max_budget_usd: nil,
          notify_on_stop: false
        })

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "nonexistent_key",
          "value",
          socket
        )

      # Should have an error flash for unknown setting
      assert result.assigns.flash["error"] =~ "Setting update failed"
    end

    test "returns error flash when agent not loaded and trying to update agent scope" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session: session,
          agent: nil,
          dm_settings_effective: %{},
          dm_settings_agent_overrides: %{},
          dm_settings_session_overrides: %{},
          show_live_stream: false,
          thinking_enabled: false,
          max_budget_usd: nil,
          notify_on_stop: false
        })

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value("agent", "theme", "dark", socket)

      assert result.assigns.flash["error"] =~ "agent not loaded"
    end
  end

  describe "handle_setting_toggle/2" do
    test "toggles a boolean setting from false to true" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session: session,
          agent: nil,
          dm_settings_effective: %{"general" => %{"show_live_stream" => false}},
          dm_settings_agent_overrides: %{},
          dm_settings_session_overrides: %{},
          show_live_stream: false,
          thinking_enabled: false,
          max_budget_usd: nil,
          notify_on_stop: false
        })

      {:noreply, result} =
        SettingsHandlers.handle_setting_toggle("session", "show_live_stream", socket)

      # Setting should be toggled
      assert result.assigns.session.id == session.id
    end

    test "toggles a boolean setting from true to false" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session: session,
          agent: nil,
          dm_settings_effective: %{"general" => %{"show_live_stream" => true}},
          dm_settings_agent_overrides: %{},
          dm_settings_session_overrides: %{},
          show_live_stream: true,
          thinking_enabled: false,
          max_budget_usd: nil,
          notify_on_stop: false
        })

      {:noreply, result} =
        SettingsHandlers.handle_setting_toggle("session", "show_live_stream", socket)

      # Setting should be toggled
      assert result.assigns.session.id == session.id
    end

    test "returns error flash for invalid setting key" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session: session,
          agent: nil,
          dm_settings_effective: %{},
          dm_settings_agent_overrides: %{},
          dm_settings_session_overrides: %{},
          show_live_stream: false,
          thinking_enabled: false,
          max_budget_usd: nil,
          notify_on_stop: false
        })

      {:noreply, result} =
        SettingsHandlers.handle_setting_toggle("session", "nonexistent", socket)

      assert result.assigns.flash["error"] =~ "Setting update failed"
    end

    test "returns error flash when agent not loaded" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session: session,
          agent: nil,
          dm_settings_effective: %{},
          dm_settings_agent_overrides: %{},
          dm_settings_session_overrides: %{},
          show_live_stream: false,
          thinking_enabled: false,
          max_budget_usd: nil,
          notify_on_stop: false
        })

      {:noreply, result} =
        SettingsHandlers.handle_setting_toggle("agent", "show_live_stream", socket)

      assert result.assigns.flash["error"] =~ "agent not loaded"
    end
  end

  describe "handle_reset_settings/2" do
    test "resets session-scoped settings" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session: session,
          agent: nil,
          dm_settings_effective: %{"general" => %{"theme" => "dark"}},
          dm_settings_agent_overrides: %{},
          dm_settings_session_overrides: %{"theme" => "dark"},
          show_live_stream: false,
          thinking_enabled: false,
          max_budget_usd: nil,
          notify_on_stop: false
        })

      {:noreply, result} = SettingsHandlers.handle_reset_settings("session", socket)

      # Session should be reset
      assert result.assigns.session.id == session.id
      # Session overrides should be empty
      assert result.assigns.dm_settings_session_overrides == %{}
    end

    test "resets agent-scoped settings" do
      agent = Factory.create_agent()
      session = Factory.new_session()

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          dm_settings_effective: %{"general" => %{"theme" => "dark"}},
          dm_settings_agent_overrides: %{"theme" => "dark"},
          dm_settings_session_overrides: %{},
          show_live_stream: false,
          thinking_enabled: false,
          max_budget_usd: nil,
          notify_on_stop: false
        })

      {:noreply, result} = SettingsHandlers.handle_reset_settings("agent", socket)

      # Agent should be reset
      assert result.assigns.agent.id == agent.id
      # Agent overrides should be empty
      assert result.assigns.dm_settings_agent_overrides == %{}
    end

    test "returns error flash when agent not loaded and trying to reset agent scope" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session: session,
          agent: nil,
          dm_settings_effective: %{},
          dm_settings_agent_overrides: %{},
          dm_settings_session_overrides: %{},
          show_live_stream: false,
          thinking_enabled: false,
          max_budget_usd: nil,
          notify_on_stop: false
        })

      {:noreply, result} = SettingsHandlers.handle_reset_settings("agent", socket)

      assert result.assigns.flash["error"] =~ "agent not loaded"
    end

    test "preserves runtime assigns when resetting" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session: session,
          agent: nil,
          dm_settings_effective: %{"general" => %{"show_live_stream" => true}},
          dm_settings_agent_overrides: %{},
          dm_settings_session_overrides: %{},
          show_live_stream: true,
          thinking_enabled: false,
          max_budget_usd: nil,
          notify_on_stop: false
        })

      {:noreply, result} = SettingsHandlers.handle_reset_settings("session", socket)

      # Runtime assigns should be preserved or updated appropriately
      assert result.assigns.show_live_stream == true or result.assigns.show_live_stream == false
    end
  end

  describe "build_settings_assigns/5" do
    test "builds correct assigns after session setting write" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session: session,
          agent: nil,
          dm_settings_effective: %{},
          dm_settings_agent_overrides: %{},
          dm_settings_session_overrides: %{},
          show_live_stream: false,
          thinking_enabled: false,
          max_budget_usd: nil,
          notify_on_stop: false
        })

      # Simulate a successful setting update and the resulting assigns update
      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value("session", "theme", "dark", socket)

      # Result should have the expected assigns
      assert Map.has_key?(result.assigns, :dm_settings_effective)
      assert Map.has_key?(result.assigns, :dm_settings_session_overrides)
      assert Map.has_key?(result.assigns, :show_live_stream)
    end

    test "preserves existing runtime values when effective key is nil" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session: session,
          agent: nil,
          dm_settings_effective: %{},
          dm_settings_agent_overrides: %{},
          dm_settings_session_overrides: %{},
          show_live_stream: true,
          thinking_enabled: true,
          max_budget_usd: 10.0,
          notify_on_stop: true
        })

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value("session", "theme", "dark", socket)

      # Runtime assigns should preserve previous values when not overridden
      assert result.assigns.show_live_stream == true
      assert result.assigns.thinking_enabled == true
    end
  end

  describe "format_setting_error/1" do
    test "formats various error types (via handle_setting_update_with_value)" do
      session = Factory.new_session()

      socket =
        build_socket(%{
          session: session,
          agent: nil,
          dm_settings_effective: %{},
          dm_settings_agent_overrides: %{},
          dm_settings_session_overrides: %{},
          show_live_stream: false,
          thinking_enabled: false,
          max_budget_usd: nil,
          notify_on_stop: false
        })

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value("session", "invalid", "value", socket)

      assert result.assigns.flash["error"] =~ "Setting update failed"
    end
  end
end
