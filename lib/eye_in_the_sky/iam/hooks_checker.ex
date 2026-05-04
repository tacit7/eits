defmodule EyeInTheSky.IAM.HooksChecker do
  @moduledoc """
  Checks whether the EITS IAM hooks are installed in the local Claude Code
  settings file (~/.claude/settings.json).

  Returns:
    :installed       — PreToolUse (the blocking event) has a hook referencing the IAM endpoint
    :not_installed   — PreToolUse hook is absent or settings.json unreadable
    :not_applicable  — not running in Tauri desktop mode; web agents use remote hooks

  Called from IAM LiveViews on mount to decide whether to show the offline banner.

  The settings path is resolved at runtime so desktop builds work correctly
  regardless of which user's home directory was active at compile time.
  """

  alias EyeInTheSky.Desktop

  @hook_marker "iam/hook"

  # PreToolUse is the critical event — it's the only one that can block a tool
  # call. PostToolUse and Stop are advisory; missing them doesn't leave the
  # system unprotected. We only suppress the banner when PreToolUse is present.
  @required_event "PreToolUse"

  @spec status() :: :installed | :not_installed | :not_applicable
  def status do
    if Desktop.desktop_mode?() do
      check_settings_file()
    else
      :not_applicable
    end
  end

  # ── private ───────────────────────────────────────────────────────────────

  # Build the path at runtime — never at compile time — so the desktop release
  # reads the actual user's home directory, not the build machine's.
  defp settings_path do
    Path.join([System.user_home!(), ".claude", "settings.json"])
  end

  defp check_settings_file do
    with {:ok, raw} <- File.read(settings_path()),
         {:ok, json} <- Jason.decode(raw),
         hooks when is_map(hooks) <- Map.get(json, "hooks", %{}) do
      if pre_tool_use_hook_present?(hooks), do: :installed, else: :not_installed
    else
      _ -> :not_installed
    end
  end

  # Check specifically that PreToolUse has a hook referencing our endpoint.
  # Other events (PostToolUse, Stop) are advisory; their absence does not
  # leave tool calls unblocked.
  defp pre_tool_use_hook_present?(hooks) when is_map(hooks) do
    hooks
    |> Map.get(@required_event, [])
    |> event_groups_have_marker?()
  end

  defp event_groups_have_marker?(groups) when is_list(groups) do
    Enum.any?(groups, fn group ->
      is_map(group) and
        Enum.any?(Map.get(group, "hooks", []), fn entry ->
          is_map(entry) and
            is_binary(Map.get(entry, "command", "")) and
            String.contains?(entry["command"], @hook_marker)
        end)
    end)
  end

  defp event_groups_have_marker?(_), do: false
end
