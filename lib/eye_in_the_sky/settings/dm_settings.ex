defmodule EyeInTheSky.Settings.DmSettings do
  @moduledoc """
  Converts an effective DM settings map to provider CLI keyword opts.
  Pure function — no DB calls.
  """

  @doc """
  Converts the effective settings map to a keyword list of CLI opts for the
  given provider. Returns an empty list for unknown providers or empty maps.

  For `"claude"`, maps `anthropic.*` keys.
  For `"codex"`, maps `openai.*` keys.
  """
  @spec to_provider_opts(map() | nil, String.t()) :: keyword()
  def to_provider_opts(nil, _provider), do: []
  def to_provider_opts(_effective, nil), do: []

  def to_provider_opts(effective, "codex") when is_map(effective) do
    effective
    |> Map.get("openai", %{})
    |> openai_opts()
  end

  def to_provider_opts(effective, "claude") when is_map(effective) do
    effective
    |> Map.get("anthropic", %{})
    |> anthropic_opts()
  end

  def to_provider_opts(_effective, _provider), do: []

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp anthropic_opts(anthropic) when is_map(anthropic) do
    [
      permission_mode: anthropic["permission_mode"],
      max_turns: anthropic["max_turns"],
      fallback_model: anthropic["fallback_model"],
      from_pr: anthropic["from_pr"],
      json_schema: anthropic["json_schema"],
      allowed_tools: anthropic["allowed_tools"],
      permission_prompt_tool: anthropic["permission_prompt_tool"],
      add_dir: anthropic["add_dir"],
      mcp_config: anthropic["mcp_config"],
      plugin_dir: anthropic["plugin_dir"],
      settings_file: anthropic["settings_file"],
      agents_json: anthropic["agents_json"],
      system_prompt: anthropic["system_prompt"],
      system_prompt_file: anthropic["system_prompt_file"],
      append_system_prompt: anthropic["append_system_prompt"],
      append_system_prompt_file: anthropic["append_system_prompt_file"],
      debug: anthropic["debug_categories"],
      bare: anthropic["bare"],
      verbose: anthropic["verbose"],
      include_partial_messages: anthropic["include_partial_messages"],
      no_session_persistence: anthropic["no_session_persistence"],
      chrome: to_chrome_bool(anthropic["chrome"]),
      sandbox: anthropic["sandbox"],
      skip_permissions: anthropic["dangerously_skip_permissions"]
    ]
    |> Keyword.filter(fn {_k, v} -> not is_nil(v) end)
  end

  defp anthropic_opts(_), do: []

  # Include boolean false values explicitly so RuntimeContext.build/3 can
  # distinguish "user set this to false" from "not specified".
  defp openai_opts(openai) when is_map(openai) do
    []
    |> maybe_put(:ask_for_approval, openai["ask_for_approval"])
    |> maybe_put(:sandbox, openai["sandbox"])
    |> maybe_put(:full_auto, openai["full_auto"])
    |> maybe_put(:bypass_sandbox, openai["dangerously_bypass_approvals_and_sandbox"])
  end

  defp openai_opts(_), do: []

  # Include booleans (even false) but skip nil — nil means "not configured".
  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp to_chrome_bool("on"), do: true
  defp to_chrome_bool("off"), do: false
  defp to_chrome_bool(_), do: nil
end
