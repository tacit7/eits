defmodule EyeInTheSky.Claude.CLI.Args do
  @moduledoc """
  Builds and validates CLI argument lists for the Claude binary.

  Extracted from `EyeInTheSky.Claude.CLI` to separate argument construction
  and validation from OS process spawning. `CLI` delegates all arg/validation
  functions here; callers should continue to use the `CLI` public API.
  """

  require Logger

  @known_permission_modes ~w(acceptEdits bypassPermissions default delegate dontAsk plan)
  @redacted_flags ~w(-p --system-prompt --append-system-prompt)

  # ---------------------------------------------------------------------------
  # Normalization & validation
  # ---------------------------------------------------------------------------

  @doc """
  Normalize key aliases and coerce types before validation.

  - `:allowed_tools` is converted to `:allowedTools`
  - String booleans `"true"`/`"false"` are coerced to actual booleans
    for `:skip_permissions` and `:verbose`
  """
  @spec normalize_opts(keyword()) :: keyword()
  def normalize_opts(opts) do
    opts
    |> normalize_allowed_tools()
    |> coerce_booleans([:skip_permissions, :verbose])
  end

  @doc """
  Validate option values. Returns `:ok` or `{:error, {key, reason}}`.

  - `:prompt` must be a non-empty binary when present (nil is allowed)
  - `:max_turns` must be a positive integer when present
  - `:permission_mode` must be a known mode or nil/""
  - Boolean keys must be actual booleans when present
  """
  @spec validate_opts(keyword()) :: :ok | {:error, {atom(), String.t()}}
  def validate_opts(opts) do
    with :ok <- validate_prompt(opts[:prompt]),
         :ok <- validate_max_turns(opts[:max_turns]),
         :ok <- validate_permission_mode(opts[:permission_mode]),
         :ok <- validate_boolean(opts, :skip_permissions) do
      validate_boolean(opts, :verbose)
    end
  end

  # ---------------------------------------------------------------------------
  # Arg builder
  # ---------------------------------------------------------------------------

  @doc """
  Builds a flat list of CLI args from a keyword list.

  Supported keys (all optional unless noted):

    * `:prompt` (required) - the user prompt, becomes `-p <prompt>`
    * `:session_id` - `--session-id <id>` (for new sessions)
    * `:resume` - `--resume <session_id>`
    * `:model` - `--model <model>`
    * `:output_format` - `--output-format <fmt>` (default: "stream-json")
    * `:verbose` - `--verbose` (forced true when output_format is "stream-json")
    * `:skip_permissions` - `--dangerously-skip-permissions` (default: true)
    * `:max_turns` - `--max-turns <n>`
    * `:system_prompt` - `--system-prompt <text>`
    * `:append_system_prompt` - `--append-system-prompt <text>`
    * `:allowedTools` - `--allowedTools <csv>`
    * `:permission_mode` - `--permission-mode <mode>`
    * `:mcp_config` - `--mcp-config <path>`
    * `:add_dir` - `--add-dir <path>`
    * `:plugin_dir` - `--plugin-dir <path>`
    * `:settings_file` - `--settings <file>`
    * `:name` - `--name <name>` (session display name)
    * `:sandbox` - `true` → `--sandbox`
    * `:chrome` - `true` → `--chrome`, `false` → `--no-chrome`

  Unknown keys are silently ignored.
  """
  @spec build_args(keyword()) :: [String.t()]
  def build_args(caller_opts) do
    # Filter nils from caller opts (nil = "not specified", allows DB/fallback to win)
    caller = Keyword.filter(caller_opts, fn {_k, v} -> v != nil end)

    # Three-way merge: hardcoded fallbacks < DB settings < caller opts
    opts =
      [output_format: "stream-json"]
      |> Keyword.merge(cli_db_defaults())
      |> Keyword.merge(caller)

    args = []

    # Session mode flags (mutually exclusive: resume > new)
    args =
      cond do
        resume_id = opts[:resume] ->
          args ++ ["--resume", to_string(resume_id)]

        session_id = opts[:session_id] ->
          args ++ ["--session-id", to_string(session_id)]

        true ->
          args
      end

    # Prompt
    args = args ++ ["-p", opts[:prompt]]

    # Value flags
    args = maybe_flag(args, "--output-format", opts[:output_format])
    args = maybe_flag(args, "--model", normalize_model_name(opts[:model]))
    args = maybe_flag(args, "--max-turns", opts[:max_turns])
    args = maybe_flag(args, "--system-prompt", opts[:system_prompt])
    args = maybe_flag(args, "--append-system-prompt", opts[:append_system_prompt])
    args = maybe_flag(args, "--allowedTools", opts[:allowedTools])
    args = maybe_flag(args, "--permission-mode", opts[:permission_mode])
    args = maybe_flag(args, "--mcp-config", opts[:mcp_config])
    args = maybe_flag(args, "--thinking-budget-tokens", opts[:thinking_budget])
    args = maybe_flag(args, "--max-budget-usd", opts[:max_budget_usd])
    args = maybe_flag(args, "--agent", opts[:agent])
    args = maybe_flag(args, "--add-dir", opts[:add_dir])
    args = maybe_flag(args, "--plugin-dir", opts[:plugin_dir])
    args = maybe_flag(args, "--settings", opts[:settings_file])
    args = maybe_flag(args, "--name", opts[:name])

    # Boolean flags — stream-json requires --verbose for proper output parsing
    verbose = opts[:verbose] || opts[:output_format] == "stream-json"

    args =
      args
      |> maybe_bool_flag("--verbose", verbose)
      |> maybe_bool_flag("--dangerously-skip-permissions", opts[:skip_permissions])
      |> maybe_bool_flag("--sandbox", opts[:sandbox] == true)
      |> maybe_bool_flag("--chrome", opts[:chrome] == true)
      |> maybe_bool_flag("--no-chrome", opts[:chrome] == false)
      |> maybe_bool_flag("--include-partial-messages", opts[:include_partial_messages])

    # When multimodal content blocks are present, switch to stdin input mode.
    args =
      if has_content_blocks?(opts) do
        args ++ ["--input-format", "stream-json"]
      else
        args
      end

    args
  end

  @doc """
  Serializes content blocks to a JSON message suitable for Claude CLI stdin input.

  Returns `nil` when no content blocks are present (text-only message).
  When content blocks exist, returns a JSON string containing a user message
  with the text prompt and all formatted content blocks as the content array.
  """
  @spec content_blocks_json(keyword()) :: String.t() | nil
  def content_blocks_json(opts) do
    case Keyword.get(opts, :content_blocks, []) do
      [] ->
        nil

      blocks when is_list(blocks) ->
        prompt = Keyword.get(opts, :prompt, "")
        content = [%{"type" => "text", "text" => prompt} | blocks]
        message = %{"type" => "user", "content" => content}
        Jason.encode!(message)
    end
  end

  # ---------------------------------------------------------------------------
  # Safe logging
  # ---------------------------------------------------------------------------

  @doc """
  Returns the list of flags whose values are redacted in log output.
  """
  @spec redacted_flags() :: [String.t()]
  def redacted_flags, do: @redacted_flags

  @doc """
  Redacts sensitive flag values from a CLI arg list for safe logging.
  """
  @spec safe_log_args([String.t()]) :: [String.t()]
  def safe_log_args([]), do: []

  def safe_log_args([flag, _value | rest]) when flag in @redacted_flags,
    do: [flag, "[REDACTED]" | safe_log_args(rest)]

  def safe_log_args([head | rest]), do: [head | safe_log_args(rest)]

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp normalize_allowed_tools(opts) do
    case Keyword.pop(opts, :allowed_tools) do
      {nil, rest} -> rest
      {val, rest} -> Keyword.put_new(rest, :allowedTools, val)
    end
  end

  defp coerce_booleans(opts, keys) do
    Enum.reduce(keys, opts, fn key, acc ->
      case Keyword.fetch(acc, key) do
        {:ok, "true"} -> Keyword.put(acc, key, true)
        {:ok, "false"} -> Keyword.put(acc, key, false)
        _ -> acc
      end
    end)
  end

  defp validate_prompt(nil), do: :ok
  defp validate_prompt(p) when is_binary(p) and byte_size(p) > 0, do: :ok
  defp validate_prompt(""), do: {:error, {:prompt, "must be a non-empty string"}}
  defp validate_prompt(_), do: {:error, {:prompt, "must be a non-empty string"}}

  defp validate_max_turns(nil), do: :ok
  defp validate_max_turns(n) when is_integer(n) and n > 0, do: :ok
  defp validate_max_turns(_), do: {:error, {:max_turns, "must be a positive integer"}}

  defp validate_permission_mode(nil), do: :ok
  defp validate_permission_mode(""), do: :ok

  defp validate_permission_mode(mode) when is_binary(mode) do
    if mode in @known_permission_modes,
      do: :ok,
      else: {:error, {:permission_mode, "unknown mode: #{mode}"}}
  end

  defp validate_permission_mode(_), do: {:error, {:permission_mode, "must be a string"}}

  defp validate_boolean(opts, key) do
    case Keyword.fetch(opts, key) do
      :error -> :ok
      {:ok, v} when is_boolean(v) -> :ok
      {:ok, _} -> {:error, {key, "must be a boolean"}}
    end
  end

  # Normalize model names from simple identifiers to full Claude model identifiers.
  defp normalize_model_name(nil), do: nil

  defp normalize_model_name(model) when is_binary(model) do
    case String.downcase(model) do
      "haiku" -> "claude-haiku-4-5"
      "sonnet" -> "claude-sonnet-4-6"
      "opus" -> "claude-opus-4-6"
      _ -> model
    end
  end

  defp has_content_blocks?(opts) do
    case Keyword.get(opts, :content_blocks, []) do
      [] -> false
      blocks when is_list(blocks) -> true
      _ -> false
    end
  end

  defp maybe_flag(args, _flag, nil), do: args
  defp maybe_flag(args, _flag, ""), do: args
  defp maybe_flag(args, flag, value), do: args ++ [flag, to_string(value)]

  defp maybe_bool_flag(args, _flag, falsy) when falsy in [nil, false], do: args
  defp maybe_bool_flag(args, flag, _truthy), do: args ++ [flag]

  defp cli_db_defaults do
    alias EyeInTheSky.Settings
    alias EyeInTheSky.Utils.ToolHelpers

    [
      model: Settings.get("model"),
      permission_mode: Settings.get("permission_mode"),
      max_turns: ToolHelpers.parse_int(Settings.get("max_turns")),
      output_format: Settings.get("output_format"),
      skip_permissions: parse_setting_boolean(Settings.get("skip_permissions"))
    ]
    |> Keyword.filter(fn {_k, v} -> v != nil end)
  rescue
    DBConnection.ConnectionError ->
      Logger.warning("[cli_db_defaults] DB unavailable, using empty defaults")
      []
  end

  defp parse_setting_boolean(nil), do: nil
  defp parse_setting_boolean("true"), do: true
  defp parse_setting_boolean("false"), do: false
  defp parse_setting_boolean(_), do: nil
end
