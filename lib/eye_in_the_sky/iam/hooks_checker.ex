defmodule EyeInTheSky.IAM.HooksChecker do
  @moduledoc """
  Checks whether the EITS IAM hooks are installed in the local Claude Code
  settings file (~/.claude/settings.json).

  Returns:
    :installed       — at least one hook command references the IAM hook endpoint
    :not_installed   — settings.json exists but IAM hooks are absent
    :not_applicable  — not running in Tauri desktop mode; web agents use remote hooks

  Called from IAM LiveViews on mount to decide whether to show the offline banner.
  """

  alias EyeInTheSky.Desktop

  @hook_marker "iam/hook"
  @settings_path Path.join([System.user_home!(), ".claude", "settings.json"])

  @spec status() :: :installed | :not_installed | :not_applicable
  def status do
    if Desktop.desktop_mode?() do
      check_settings_file()
    else
      :not_applicable
    end
  end

  # ── private ───────────────────────────────────────────────────────────────

  defp check_settings_file do
    with {:ok, raw} <- File.read(@settings_path),
         {:ok, json} <- Jason.decode(raw),
         hooks when is_map(hooks) <- Map.get(json, "hooks", %{}) do
      if any_hook_has_marker?(hooks), do: :installed, else: :not_installed
    else
      _ -> :not_installed
    end
  end

  # Walk all hook event types → hook groups → hook entries looking for the marker.
  defp any_hook_has_marker?(hooks) when is_map(hooks) do
    Enum.any?(hooks, fn {_event, groups} ->
      is_list(groups) and
        Enum.any?(groups, fn group ->
          is_map(group) and
            Enum.any?(Map.get(group, "hooks", []), fn entry ->
              is_map(entry) and
                is_binary(Map.get(entry, "command", "")) and
                String.contains?(entry["command"], @hook_marker)
            end)
        end)
    end)
  end

  defp any_hook_has_marker?(_), do: false
end
