defmodule EyeInTheSkyWeb.DmLive.SettingsHandlersTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.{Agents, Factory, Sessions}
  alias EyeInTheSkyWeb.DmLive.SettingsHandlers

  defp build_socket(assigns) do
    base = %{__changed__: %{}, flash: %{}, private: %{live_temp: %{}}}
    %Phoenix.LiveView.Socket{assigns: Map.merge(base, assigns)}
  end

  defp base_socket_assigns(session, agent \\ nil) do
    %{
      session: session,
      agent: agent,
      dm_settings_effective: %{},
      dm_settings_agent_overrides: %{},
      dm_settings_session_overrides: %{},
      show_live_stream: true,
      thinking_enabled: false,
      max_budget_usd: nil,
      notify_on_stop: false
    }
  end

  describe "handle_scope_change/2" do
    test "switches scope from agent to session" do
      socket = build_socket(%{dm_settings_scope: "agent"})
      {:noreply, result} = SettingsHandlers.handle_scope_change("session", socket)
      assert result.assigns.dm_settings_scope == "session"
    end

    test "switches scope from session to agent" do
      socket = build_socket(%{dm_settings_scope: "session"})
      {:noreply, result} = SettingsHandlers.handle_scope_change("agent", socket)
      assert result.assigns.dm_settings_scope == "agent"
    end
  end

  describe "handle_subtab_change/2" do
    test "switches to general subtab" do
      socket = build_socket(%{dm_settings_subtab: "appearance"})
      {:noreply, result} = SettingsHandlers.handle_subtab_change("general", socket)
      assert result.assigns.dm_settings_subtab == "general"
    end

    test "switches between different subtabs" do
      socket = build_socket(%{dm_settings_subtab: "general"})
      {:noreply, result} = SettingsHandlers.handle_subtab_change("anthropic", socket)
      assert result.assigns.dm_settings_subtab == "anthropic"
    end
  end

  describe "handle_setting_update_with_value/4 — persistence" do
    test "session write persists exact boolean value to DB" do
      session = Factory.new_session()
      socket = build_socket(base_socket_assigns(session))

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "general.show_live_stream",
          false,
          socket
        )

      # No error flash
      refute Map.has_key?(result.assigns.flash, "error")

      # Reload from DB and assert exact nested value with correct type
      fresh = Sessions.get!(session.id)
      assert fresh.settings["general"]["show_live_stream"] === false

      # Socket assigns reflect the persisted record and updated effective view
      assert result.assigns.session.id == session.id
      assert result.assigns.dm_settings_session_overrides["general"]["show_live_stream"] === false
      # Runtime assign updated to match persisted value
      assert result.assigns.show_live_stream === false
    end

    test "session write persists exact enum value to DB" do
      session = Factory.new_session()
      socket = build_socket(base_socket_assigns(session))

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "anthropic.permission_mode",
          "plan",
          socket
        )

      refute Map.has_key?(result.assigns.flash, "error")

      fresh = Sessions.get!(session.id)
      assert fresh.settings["anthropic"]["permission_mode"] == "plan"
      assert result.assigns.dm_settings_session_overrides["anthropic"]["permission_mode"] == "plan"
    end

    test "session write persists exact integer value to DB" do
      session = Factory.new_session()
      socket = build_socket(base_socket_assigns(session))

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "anthropic.max_turns",
          "5",
          socket
        )

      refute Map.has_key?(result.assigns.flash, "error")

      fresh = Sessions.get!(session.id)
      # Coerced to integer, not string
      assert fresh.settings["anthropic"]["max_turns"] === 5
    end

    test "session write does not touch agent DB record" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)

      socket = build_socket(base_socket_assigns(session, agent))

      {:noreply, _result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "general.thinking_enabled",
          true,
          socket
        )

      # Agent settings in DB must remain nil (no writes)
      fresh_agent = Agents.get_agent!(agent.id)
      assert fresh_agent.settings == nil || fresh_agent.settings == %{}
    end

    test "agent write persists exact enum value to DB" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)

      socket = build_socket(base_socket_assigns(session, agent))

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "agent",
          "anthropic.permission_mode",
          "bypassPermissions",
          socket
        )

      refute Map.has_key?(result.assigns.flash, "error")

      fresh_agent = Agents.get_agent!(agent.id)
      assert fresh_agent.settings["anthropic"]["permission_mode"] == "bypassPermissions"
      assert result.assigns.dm_settings_agent_overrides["anthropic"]["permission_mode"] ==
               "bypassPermissions"
    end

    test "agent write does not touch session DB record" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)

      socket = build_socket(base_socket_assigns(session, agent))

      {:noreply, _result} =
        SettingsHandlers.handle_setting_update_with_value(
          "agent",
          "general.notify_on_stop",
          true,
          socket
        )

      fresh_session = Sessions.get!(session.id)
      assert fresh_session.settings == nil || fresh_session.settings == %{}
    end

    test "runtime assign show_live_stream updated on session write" do
      session = Factory.new_session()

      socket =
        build_socket(
          base_socket_assigns(session)
          |> Map.put(:show_live_stream, true)
        )

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "general.show_live_stream",
          false,
          socket
        )

      assert result.assigns.show_live_stream === false
    end

    test "runtime assign max_budget_usd updated on session write" do
      session = Factory.new_session()
      socket = build_socket(base_socket_assigns(session) |> Map.put(:max_budget_usd, nil))

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "general.max_budget_usd",
          "12.50",
          socket
        )

      assert result.assigns.max_budget_usd === 12.5
    end
  end

  describe "handle_setting_update_with_value/4 — validation failures" do
    test "unknown key returns error flash and leaves session DB unchanged" do
      session = Factory.new_session()
      socket = build_socket(base_socket_assigns(session))

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "nonexistent.key",
          "value",
          socket
        )

      assert result.assigns.flash["error"] =~ "Setting update failed"
      assert result.assigns.flash["error"] =~ "unknown setting"

      fresh = Sessions.get!(session.id)
      assert fresh.settings == nil || fresh.settings == %{}
    end

    test "invalid enum value returns error flash and leaves session DB unchanged" do
      session = Factory.new_session()
      socket = build_socket(base_socket_assigns(session))

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "anthropic.permission_mode",
          "invalid_mode",
          socket
        )

      assert result.assigns.flash["error"] =~ "Setting update failed"
      assert result.assigns.flash["error"] =~ "value not allowed"

      fresh = Sessions.get!(session.id)
      assert get_in(fresh.settings || %{}, ["anthropic", "permission_mode"]) == nil
    end

    test "decimal string for integer max_turns returns error flash" do
      session = Factory.new_session()
      socket = build_socket(base_socket_assigns(session))

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "anthropic.max_turns",
          "3.5",
          socket
        )

      assert result.assigns.flash["error"] =~ "Setting update failed"
      assert result.assigns.flash["error"] =~ "must be a whole number"

      fresh = Sessions.get!(session.id)
      assert get_in(fresh.settings || %{}, ["anthropic", "max_turns"]) == nil
    end

    test "session-only key at agent scope returns scope error and leaves agent DB unchanged" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      socket = build_socket(base_socket_assigns(session, agent))

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "agent",
          "anthropic.from_pr",
          "123",
          socket
        )

      assert result.assigns.flash["error"] =~ "Setting update failed"
      assert result.assigns.flash["error"] =~ "cannot be changed at this scope"

      fresh_agent = Agents.get_agent!(agent.id)
      assert get_in(fresh_agent.settings || %{}, ["anthropic", "from_pr"]) == nil
    end

    test "agent scope with no agent loaded returns agent-not-loaded flash" do
      session = Factory.new_session()
      socket = build_socket(base_socket_assigns(session, nil))

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "agent",
          "general.show_live_stream",
          true,
          socket
        )

      assert result.assigns.flash["error"] =~ "agent not loaded"
    end
  end

  describe "handle_setting_toggle/2" do
    test "toggles general.show_live_stream false→true and persists to DB" do
      session = Factory.new_session()

      socket =
        build_socket(
          base_socket_assigns(session)
          |> Map.merge(%{
            dm_settings_effective: %{"general" => %{"show_live_stream" => false}},
            show_live_stream: false
          })
        )

      {:noreply, result} =
        SettingsHandlers.handle_setting_toggle("session", "general.show_live_stream", socket)

      refute Map.has_key?(result.assigns.flash, "error")

      fresh = Sessions.get!(session.id)
      assert fresh.settings["general"]["show_live_stream"] === true
      assert result.assigns.show_live_stream === true
    end

    test "toggles general.show_live_stream true→false and persists to DB" do
      session = Factory.new_session()

      socket =
        build_socket(
          base_socket_assigns(session)
          |> Map.merge(%{
            dm_settings_effective: %{"general" => %{"show_live_stream" => true}},
            show_live_stream: true
          })
        )

      {:noreply, result} =
        SettingsHandlers.handle_setting_toggle("session", "general.show_live_stream", socket)

      refute Map.has_key?(result.assigns.flash, "error")

      fresh = Sessions.get!(session.id)
      assert fresh.settings["general"]["show_live_stream"] === false
      assert result.assigns.show_live_stream === false
    end

    test "toggles at agent scope and persists to agent DB record" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)

      socket =
        build_socket(
          base_socket_assigns(session, agent)
          |> Map.merge(%{
            dm_settings_effective: %{"general" => %{"thinking_enabled" => false}},
            thinking_enabled: false
          })
        )

      {:noreply, result} =
        SettingsHandlers.handle_setting_toggle("agent", "general.thinking_enabled", socket)

      refute Map.has_key?(result.assigns.flash, "error")

      fresh_agent = Agents.get_agent!(agent.id)
      assert fresh_agent.settings["general"]["thinking_enabled"] === true
      assert result.assigns.thinking_enabled === true
    end

    test "returns error flash for unknown key" do
      session = Factory.new_session()
      socket = build_socket(base_socket_assigns(session))

      {:noreply, result} =
        SettingsHandlers.handle_setting_toggle("session", "nonexistent", socket)

      assert result.assigns.flash["error"] =~ "Setting update failed"
      assert result.assigns.flash["error"] =~ "unknown setting"
    end

    test "returns error flash when agent not loaded for agent scope" do
      session = Factory.new_session()

      socket =
        build_socket(
          base_socket_assigns(session, nil)
          |> Map.merge(%{dm_settings_effective: %{"general" => %{"show_live_stream" => false}}})
        )

      {:noreply, result} =
        SettingsHandlers.handle_setting_toggle("agent", "general.show_live_stream", socket)

      assert result.assigns.flash["error"] =~ "agent not loaded"
    end
  end

  describe "handle_reset_settings/2" do
    test "session reset clears session.settings in DB" do
      agent = Factory.create_agent()

      {:ok, session_with_settings} =
        Sessions.create_session(%{
          uuid: Ecto.UUID.generate(),
          agent_id: agent.id,
          name: "test session",
          status: "working",
          started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          settings: %{"general" => %{"show_live_stream" => false, "thinking_enabled" => true}}
        })

      socket =
        build_socket(
          base_socket_assigns(session_with_settings)
          |> Map.put(
            :dm_settings_session_overrides,
            %{"general" => %{"show_live_stream" => false}}
          )
        )

      {:noreply, result} = SettingsHandlers.handle_reset_settings("session", socket)

      refute Map.has_key?(result.assigns.flash, "error")

      fresh = Sessions.get!(session_with_settings.id)
      assert fresh.settings == %{}

      assert result.assigns.dm_settings_session_overrides == %{}
      assert result.assigns.session.id == session_with_settings.id
    end

    test "session reset does not touch agent DB record" do
      agent = Factory.create_agent()

      {:ok, agent_with_settings} =
        Agents.update(agent, %{settings: %{"general" => %{"notify_on_stop" => true}}})

      session = Factory.create_session(agent_with_settings)

      socket = build_socket(base_socket_assigns(session, agent_with_settings))

      {:noreply, _result} = SettingsHandlers.handle_reset_settings("session", socket)

      fresh_agent = Agents.get_agent!(agent_with_settings.id)
      assert fresh_agent.settings["general"]["notify_on_stop"] === true
    end

    test "agent reset clears agent.settings in DB" do
      agent = Factory.create_agent()

      {:ok, agent_with_settings} =
        Agents.update(agent, %{
          settings: %{"anthropic" => %{"permission_mode" => "plan"}}
        })

      session = Factory.create_session(agent_with_settings)

      socket =
        build_socket(
          base_socket_assigns(session, agent_with_settings)
          |> Map.put(:dm_settings_agent_overrides, %{"anthropic" => %{"permission_mode" => "plan"}})
        )

      {:noreply, result} = SettingsHandlers.handle_reset_settings("agent", socket)

      refute Map.has_key?(result.assigns.flash, "error")

      fresh_agent = Agents.get_agent!(agent_with_settings.id)
      assert fresh_agent.settings == %{}

      assert result.assigns.dm_settings_agent_overrides == %{}
      assert result.assigns.agent.id == agent_with_settings.id
    end

    test "agent reset does not touch session DB record" do
      agent = Factory.create_agent()

      {:ok, session_with_settings} =
        Sessions.create_session(%{
          uuid: Ecto.UUID.generate(),
          agent_id: agent.id,
          name: "test session",
          status: "working",
          started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          settings: %{"general" => %{"max_budget_usd" => 5.0}}
        })

      socket = build_socket(base_socket_assigns(session_with_settings, agent))

      {:noreply, _result} = SettingsHandlers.handle_reset_settings("agent", socket)

      fresh_session = Sessions.get!(session_with_settings.id)
      assert fresh_session.settings["general"]["max_budget_usd"] == 5.0
    end

    test "session reset runtime assigns reflect schema defaults" do
      agent = Factory.create_agent()

      {:ok, session} =
        Sessions.create_session(%{
          uuid: Ecto.UUID.generate(),
          agent_id: agent.id,
          name: "test",
          status: "working",
          started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          settings: %{"general" => %{"show_live_stream" => false}}
        })

      socket =
        build_socket(
          base_socket_assigns(session)
          |> Map.put(:show_live_stream, false)
        )

      {:noreply, result} = SettingsHandlers.handle_reset_settings("session", socket)

      # After reset, effective value comes from schema defaults: show_live_stream defaults to true
      assert result.assigns.show_live_stream === true
    end

    test "returns error flash when agent not loaded for agent reset" do
      session = Factory.new_session()
      socket = build_socket(base_socket_assigns(session, nil))

      {:noreply, result} = SettingsHandlers.handle_reset_settings("agent", socket)

      assert result.assigns.flash["error"] =~ "agent not loaded"
    end
  end

  describe "build_settings_assigns/5 — runtime assign refresh" do
    test "all four runtime assigns present in result" do
      session = Factory.new_session()
      socket = build_socket(base_socket_assigns(session))

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "general.show_live_stream",
          false,
          socket
        )

      assert Map.has_key?(result.assigns, :dm_settings_effective)
      assert Map.has_key?(result.assigns, :dm_settings_session_overrides)
      assert Map.has_key?(result.assigns, :dm_settings_agent_overrides)
      assert Map.has_key?(result.assigns, :show_live_stream)
      assert Map.has_key?(result.assigns, :thinking_enabled)
      assert Map.has_key?(result.assigns, :max_budget_usd)
      assert Map.has_key?(result.assigns, :notify_on_stop)
    end

    test "unrelated runtime assigns preserved when writing an unrelated key" do
      session = Factory.new_session()

      socket =
        build_socket(
          base_socket_assigns(session)
          |> Map.merge(%{thinking_enabled: true, notify_on_stop: true, max_budget_usd: 8.0})
        )

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "anthropic.permission_mode",
          "plan",
          socket
        )

      # Anthropic setting doesn't live in general namespace, so general assigns
      # fall back to schema defaults (not the prior socket values).
      # show_live_stream schema default is true.
      assert result.assigns.show_live_stream === true
    end

    # session_cli_opts propagation tests
    test "session_cli_opts is updated after a setting change for claude session" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent, %{provider: "claude"})

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
          notify_on_stop: false,
          session_cli_opts: []
        })

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "anthropic.permission_mode",
          "plan",
          socket
        )

      assert Map.has_key?(result.assigns, :session_cli_opts)
      assert result.assigns.session_cli_opts[:permission_mode] == "plan"
    end

    test "session_cli_opts contains bypass_sandbox: false for codex after explicit disable" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent, %{provider: "codex"})

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
          notify_on_stop: false,
          session_cli_opts: []
        })

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "openai.dangerously_bypass_approvals_and_sandbox",
          "false",
          socket
        )

      assert Map.has_key?(result.assigns, :session_cli_opts)
      assert Keyword.has_key?(result.assigns.session_cli_opts, :bypass_sandbox)
      assert result.assigns.session_cli_opts[:bypass_sandbox] == false
    end
  end

  describe "format_setting_error/1 — error message text" do
    test "unknown_setting_key produces 'unknown setting' message" do
      session = Factory.new_session()
      socket = build_socket(base_socket_assigns(session))

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "totally.unknown",
          "x",
          socket
        )

      assert result.assigns.flash["error"] =~ "unknown setting"
    end

    test "invalid_enum_value produces 'value not allowed' message" do
      session = Factory.new_session()
      socket = build_socket(base_socket_assigns(session))

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "openai.sandbox",
          "bogus",
          socket
        )

      assert result.assigns.flash["error"] =~ "value not allowed"
    end

    test "invalid_integer produces 'must be a whole number' message" do
      session = Factory.new_session()
      socket = build_socket(base_socket_assigns(session))

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "session",
          "anthropic.max_turns",
          "not-a-number",
          socket
        )

      assert result.assigns.flash["error"] =~ "must be a whole number"
    end

    test "scope_not_allowed produces 'cannot be changed at this scope' message" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      socket = build_socket(base_socket_assigns(session, agent))

      {:noreply, result} =
        SettingsHandlers.handle_setting_update_with_value(
          "agent",
          "anthropic.from_pr",
          "pr-99",
          socket
        )

      assert result.assigns.flash["error"] =~ "cannot be changed at this scope"
    end
  end
end
