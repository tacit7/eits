defmodule EyeInTheSkyWeb.DmLive.SettingsHandlers do
  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias EyeInTheSky.{Agents, Sessions}
  alias EyeInTheSky.Settings.JsonSettings

  def handle_scope_change(scope, socket) do
    {:noreply, assign(socket, :dm_settings_scope, scope)}
  end

  def handle_subtab_change(subtab, socket) do
    {:noreply, assign(socket, :dm_settings_subtab, subtab)}
  end

  def handle_setting_update_with_value(scope, key, value, socket) do
    case persist_setting_update(scope, key, value, socket.assigns) do
      {:ok, assigns} ->
        {:noreply, assign(socket, assigns)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Setting update failed: #{format_setting_error(reason)}")}
    end
  end

  def handle_setting_toggle(scope, key, socket) do
    current = JsonSettings.get_setting(socket.assigns.dm_settings_effective || %{}, key)
    new_value = not (current == true)

    case persist_setting_update(scope, key, new_value, socket.assigns) do
      {:ok, assigns} ->
        {:noreply, assign(socket, assigns)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Setting update failed: #{format_setting_error(reason)}")}
    end
  end

  def handle_reset_settings(scope, socket) do
    case reset_scoped_settings(scope, socket.assigns) do
      {:ok, assigns} ->
        {:noreply, assign(socket, assigns)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Reset failed: #{format_setting_error(reason)}")}
    end
  end

  defp persist_setting_update("session", key, value, assigns) do
    with {:ok, fresh_session} <- Sessions.put_setting(assigns.session, key, value) do
      agent_settings = (assigns.agent && assigns.agent.settings) || %{}
      session_settings = fresh_session.settings || %{}

      {:ok,
       build_settings_assigns(:session, fresh_session, agent_settings, session_settings, assigns)}
    end
  end

  defp persist_setting_update("agent", _key, _value, %{agent: nil}),
    do: {:error, :no_agent_loaded}

  defp persist_setting_update("agent", key, value, assigns) do
    with {:ok, fresh_agent} <- Agents.put_setting(assigns.agent, key, value) do
      agent_settings = fresh_agent.settings || %{}
      session_settings = (assigns.session && assigns.session.settings) || %{}

      {:ok,
       build_settings_assigns(:agent, fresh_agent, agent_settings, session_settings, assigns)}
    end
  end

  defp reset_scoped_settings("session", assigns) do
    with {:ok, fresh_session} <- Sessions.reset_settings(assigns.session) do
      agent_settings = (assigns.agent && assigns.agent.settings) || %{}
      {:ok, build_settings_assigns(:session, fresh_session, agent_settings, %{}, assigns)}
    end
  end

  defp reset_scoped_settings("agent", %{agent: nil}), do: {:error, :no_agent_loaded}

  defp reset_scoped_settings("agent", assigns) do
    with {:ok, fresh_agent} <- Agents.reset_settings(assigns.agent) do
      session_settings = (assigns.session && assigns.session.settings) || %{}
      {:ok, build_settings_assigns(:agent, fresh_agent, %{}, session_settings, assigns)}
    end
  end

  # Build the full assign map after a settings write. CRITICAL: this updates
  # both the dm_settings_* introspection assigns AND the runtime assigns
  # (:thinking_enabled, :max_budget_usd, :show_live_stream, :notify_on_stop)
  # that message handlers and stream code read. Without this, settings changes
  # only take effect on remount.
  defp build_settings_assigns(
         written_scope,
         fresh_record,
         agent_settings,
         session_settings,
         assigns
       ) do
    effective = JsonSettings.effective_settings(agent_settings, session_settings)
    general = Map.get(effective, "general", %{})

    # Preserve current runtime values when the effective key is nil (e.g.
    # max_budget_usd has nil as a legitimate "no limit" default).
    base = %{
      dm_settings_effective: effective,
      dm_settings_agent_overrides: agent_settings,
      dm_settings_session_overrides: session_settings,
      show_live_stream: Map.get(general, "show_live_stream", assigns.show_live_stream),
      thinking_enabled: Map.get(general, "thinking_enabled", assigns.thinking_enabled),
      max_budget_usd: Map.get(general, "max_budget_usd", assigns.max_budget_usd),
      notify_on_stop: Map.get(general, "notify_on_stop", assigns.notify_on_stop)
    }

    case written_scope do
      :session -> Map.put(base, :session, fresh_record)
      :agent -> Map.put(base, :agent, fresh_record)
    end
  end

  defp format_setting_error(:unknown_setting_key), do: "unknown setting"

  defp format_setting_error(:scope_not_allowed),
    do: "this setting cannot be changed at this scope"

  defp format_setting_error(:invalid_float), do: "must be a number"
  defp format_setting_error(:invalid_integer), do: "must be a whole number"
  defp format_setting_error(:invalid_enum_value), do: "value not allowed"
  defp format_setting_error(:type_mismatch), do: "wrong type"
  defp format_setting_error(:no_agent_loaded), do: "agent not loaded"
  defp format_setting_error(%Ecto.Changeset{} = cs), do: inspect(cs.errors)
  defp format_setting_error(other), do: inspect(other)
end
