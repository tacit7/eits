defmodule EyeInTheSky.Claude.CLIBuildArgsTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.Claude.CLI
  alias EyeInTheSky.Settings

  setup do
    CLI.clear_binary_cache()
    :ok
  end

  # ---------------------------------------------------------------------------
  # normalize_opts/1
  # ---------------------------------------------------------------------------

  describe "normalize_opts/1" do
    test "converts :allowed_tools to :allowedTools" do
      opts = CLI.normalize_opts(allowed_tools: "Bash,Read")
      assert opts[:allowedTools] == "Bash,Read"
      refute Keyword.has_key?(opts, :allowed_tools)
    end

    test "existing :allowedTools is not overwritten by :allowed_tools" do
      opts = CLI.normalize_opts(allowedTools: "Write", allowed_tools: "Bash")
      assert opts[:allowedTools] == "Write"
    end

    test ~s(string "true"/"false" coerced to booleans) do
      opts = CLI.normalize_opts(skip_permissions: "true", verbose: "false")
      assert opts[:skip_permissions] == true
      assert opts[:verbose] == false
    end

    test "actual booleans left unchanged" do
      opts = CLI.normalize_opts(skip_permissions: true, verbose: false)
      assert opts[:skip_permissions] == true
      assert opts[:verbose] == false
    end

    test "unknown keys passed through untouched" do
      opts = CLI.normalize_opts(eits_session_id: "abc", effort_level: "high")
      assert opts[:eits_session_id] == "abc"
      assert opts[:effort_level] == "high"
    end
  end

  # ---------------------------------------------------------------------------
  # validate_opts/1
  # ---------------------------------------------------------------------------

  describe "validate_opts/1" do
    test "valid opts returns :ok" do
      assert :ok = CLI.validate_opts(prompt: "hello", max_turns: 5, permission_mode: "plan")
    end

    test "empty string prompt returns error" do
      assert {:error, {:prompt, _}} = CLI.validate_opts(prompt: "")
    end

    test "non-string prompt returns error" do
      assert {:error, {:prompt, _}} = CLI.validate_opts(prompt: 123)
    end

    test "nil prompt returns :ok" do
      assert :ok = CLI.validate_opts(prompt: nil)
    end

    test "negative max_turns returns error" do
      assert {:error, {:max_turns, _}} = CLI.validate_opts(max_turns: -1)
    end

    test "zero max_turns returns error" do
      assert {:error, {:max_turns, _}} = CLI.validate_opts(max_turns: 0)
    end

    test "float max_turns returns error" do
      assert {:error, {:max_turns, _}} = CLI.validate_opts(max_turns: 2.5)
    end

    test "unknown permission_mode returns error" do
      assert {:error, {:permission_mode, _}} = CLI.validate_opts(permission_mode: "yolo")
    end

    test "all known permission_modes accepted" do
      for mode <- ~w(acceptEdits bypassPermissions default delegate dontAsk plan) do
        assert :ok = CLI.validate_opts(permission_mode: mode)
      end
    end

    test "non-boolean skip_permissions returns error" do
      assert {:error, {:skip_permissions, _}} = CLI.validate_opts(skip_permissions: "yes")
    end

    test "empty opts returns :ok" do
      assert :ok = CLI.validate_opts([])
    end
  end

  # ---------------------------------------------------------------------------
  # safe_log_args/1
  # ---------------------------------------------------------------------------

  describe "safe_log_args/1" do
    test "redacts -p value" do
      assert CLI.safe_log_args(["-p", "secret prompt"]) == ["-p", "[REDACTED]"]
    end

    test "redacts --system-prompt value" do
      result = CLI.safe_log_args(["--model", "sonnet", "--system-prompt", "secret"])
      assert result == ["--model", "sonnet", "--system-prompt", "[REDACTED]"]
    end

    test "redacts --append-system-prompt value" do
      result = CLI.safe_log_args(["--append-system-prompt", "extra secret"])
      assert result == ["--append-system-prompt", "[REDACTED]"]
    end

    test "empty args returns empty" do
      assert CLI.safe_log_args([]) == []
    end

    test "non-sensitive args pass through unchanged" do
      args = ["--model", "sonnet", "--verbose", "--max-turns", "5"]
      assert CLI.safe_log_args(args) == args
    end
  end

  # ---------------------------------------------------------------------------
  # clear_binary_cache/0
  # ---------------------------------------------------------------------------

  describe "clear_binary_cache/0" do
    test "returns :ok when cache is empty" do
      assert :ok = CLI.clear_binary_cache()
    end
  end

  # ---------------------------------------------------------------------------
  # build_args/1 three-way merge
  # ---------------------------------------------------------------------------

  describe "build_args/1 three-way merge" do
    test "with no DB settings, caller opts produce correct flags" do
      args = CLI.build_args(prompt: "hello", model: "sonnet")

      assert "-p" in args
      assert "hello" in args
      assert "--model" in args
      assert "claude-sonnet-4-6" in args
    end

    test "DB model appears when caller doesn't specify model" do
      Settings.set_cli_defaults(%{"model" => "opus"})

      args = CLI.build_args(prompt: "test")

      assert "--model" in args
      assert "claude-opus-4-6" in args
    end

    test "caller model overrides DB model and gets normalized" do
      Settings.set_cli_defaults(%{"model" => "opus"})

      args = CLI.build_args(prompt: "test", model: "haiku")

      assert "--model" in args
      assert "claude-haiku-4-5" in args
      refute "opus" in args
    end

    test "caller nil does NOT override DB value" do
      Settings.set_cli_defaults(%{"model" => "opus"})

      args = CLI.build_args(prompt: "test", model: nil)

      assert "--model" in args
      assert "claude-opus-4-6" in args
    end

    test "model names are normalized to full Claude identifiers" do
      test_cases = [
        {"haiku", "claude-haiku-4-5"},
        {"sonnet", "claude-sonnet-4-6"},
        {"opus", "claude-opus-4-6"},
        # case insensitive
        {"HAIKU", "claude-haiku-4-5"},
        # passthrough for unknown models
        {"custom-model", "custom-model"},
        # nil passthrough
        {nil, nil}
      ]

      for {input, expected} <- test_cases do
        args = CLI.build_args(prompt: "test", model: input)

        if expected do
          assert "--model" in args
          assert expected in args
        else
          refute "--model" in args
        end
      end
    end

    test "prompt always present as -p <text>" do
      args = CLI.build_args(prompt: "do stuff")

      idx = Enum.find_index(args, &(&1 == "-p"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "do stuff"
    end
  end

  # ---------------------------------------------------------------------------
  # build_args/1 boolean flags
  # ---------------------------------------------------------------------------

  describe "build_args/1 boolean flags" do
    test "skip_permissions true produces --dangerously-skip-permissions" do
      args = CLI.build_args(prompt: "x", skip_permissions: true)

      assert "--dangerously-skip-permissions" in args
    end

    test "skip_permissions false omits the flag" do
      Settings.set_cli_defaults(%{"skip_permissions" => false})

      args = CLI.build_args(prompt: "x", skip_permissions: false)

      refute "--dangerously-skip-permissions" in args
    end

    test "verbose true produces --verbose" do
      args = CLI.build_args(prompt: "x", verbose: true)

      assert "--verbose" in args
    end

    test "verbose false omits --verbose when output_format is not stream-json" do
      args = CLI.build_args(prompt: "x", verbose: false, output_format: "json")

      refute "--verbose" in args
    end
  end

  # ---------------------------------------------------------------------------
  # build_args/1 value flags
  # ---------------------------------------------------------------------------

  describe "build_args/1 value flags" do
    test "max_turns produces --max-turns <n>" do
      args = CLI.build_args(prompt: "x", max_turns: 5)

      idx = Enum.find_index(args, &(&1 == "--max-turns"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "5"
    end

    test "output_format produces --output-format <fmt>" do
      args = CLI.build_args(prompt: "x", output_format: "json")

      idx = Enum.find_index(args, &(&1 == "--output-format"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "json"
    end

    test "default output_format from fallback when caller omits it" do
      # No DB setting, no caller arg -- fallback is "stream-json"
      args = CLI.build_args(prompt: "x")

      idx = Enum.find_index(args, &(&1 == "--output-format"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "stream-json"
    end

    test "name produces --name <value>" do
      args = CLI.build_args(prompt: "x", name: "My Agent")

      idx = Enum.find_index(args, &(&1 == "--name"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "My Agent"
    end

    test "nil name omits --name flag" do
      args = CLI.build_args(prompt: "x", name: nil)

      refute "--name" in args
    end
  end

  # ---------------------------------------------------------------------------
  # build_args/1 DB defaults for non-model flags
  # ---------------------------------------------------------------------------

  describe "build_args/1 DB defaults for non-model flags" do
    test "DB permission_mode appears when caller omits it" do
      Settings.set_cli_defaults(%{"permission_mode" => "plan"})

      args = CLI.build_args(prompt: "x")

      idx = Enum.find_index(args, &(&1 == "--permission-mode"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "plan"
    end

    test "DB max_turns appears when caller omits it" do
      Settings.set_cli_defaults(%{"max_turns" => 8})

      args = CLI.build_args(prompt: "x")

      idx = Enum.find_index(args, &(&1 == "--max-turns"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "8"
    end

    test "DB skip_permissions false overrides fallback true" do
      Settings.set_cli_defaults(%{"skip_permissions" => false})

      args = CLI.build_args(prompt: "x")

      refute "--dangerously-skip-permissions" in args
    end
  end

  # ---------------------------------------------------------------------------
  # build_args/1 session mode flags
  # ---------------------------------------------------------------------------

  describe "build_args/1 session mode flags" do
    test "resume produces --resume <id>" do
      args = CLI.build_args(prompt: "x", resume: "abc-123")

      idx = Enum.find_index(args, &(&1 == "--resume"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "abc-123"
      refute "-c" in args
    end

    test "session_id produces --session-id <id>" do
      args = CLI.build_args(prompt: "x", session_id: "sess-456")

      idx = Enum.find_index(args, &(&1 == "--session-id"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "sess-456"
    end

    test "resume takes priority over session_id" do
      args = CLI.build_args(prompt: "x", resume: "r-1", session_id: "s-1")

      assert "--resume" in args
      refute "--session-id" in args
    end
  end

  # ---------------------------------------------------------------------------
  # build_args/1 with allowed_tools alias
  # ---------------------------------------------------------------------------

  describe "build_args/1 with allowed_tools alias" do
    test "after normalize, :allowed_tools produces --allowedTools flag" do
      normalized = CLI.normalize_opts(prompt: "x", allowed_tools: "Bash,Read")
      args = CLI.build_args(normalized)

      idx = Enum.find_index(args, &(&1 == "--allowedTools"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "Bash,Read"
    end
  end

  # ---------------------------------------------------------------------------
  # stream-json forces --verbose
  # ---------------------------------------------------------------------------

  describe "build_args/1 stream-json verbose invariant" do
    test "stream-json output_format forces --verbose even when verbose not set" do
      args = CLI.build_args(prompt: "x", output_format: "stream-json")

      assert "--verbose" in args
    end

    test "stream-json from DB default forces --verbose" do
      # Default fallback is stream-json, so --verbose should always appear
      args = CLI.build_args(prompt: "x")

      assert "--verbose" in args
    end

    test "json output_format does NOT force --verbose" do
      args = CLI.build_args(prompt: "x", output_format: "json", verbose: false)

      refute "--verbose" in args
    end

    test "explicit verbose: false still loses to stream-json" do
      args = CLI.build_args(prompt: "x", output_format: "stream-json", verbose: false)

      assert "--verbose" in args
    end
  end

  # ---------------------------------------------------------------------------
  # Multimodal content blocks
  # ---------------------------------------------------------------------------

  describe "build_args with content_blocks" do
    test "adds --input-format stream-json when content_blocks present" do
      blocks = [
        %{
          "type" => "image",
          "source" => %{"type" => "base64", "media_type" => "image/png", "data" => "abc"}
        }
      ]

      args = CLI.build_args(prompt: "describe this", content_blocks: blocks)

      assert "--input-format" in args
      assert "stream-json" in args
    end

    test "does not add --input-format when content_blocks is empty" do
      args = CLI.build_args(prompt: "hello", content_blocks: [])

      # Should only have the output-format stream-json, not input-format
      {_flag_indices, input_format_count} =
        args
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.reduce({[], 0}, fn
          ["--input-format", _], {acc, count} -> {acc, count + 1}
          _, {acc, count} -> {acc, count}
        end)

      assert input_format_count == 0
    end

    test "does not add --input-format when no content_blocks key" do
      args = CLI.build_args(prompt: "hello")

      refute "--input-format" in args
    end
  end

  # ---------------------------------------------------------------------------
  # build_args/1 advanced CLI flags (form-submitted)
  # ---------------------------------------------------------------------------

  describe "build_args/1 advanced CLI flags" do
    test "chrome: true produces --chrome" do
      args = CLI.build_args(prompt: "x", chrome: true)
      assert "--chrome" in args
      refute "--no-chrome" in args
    end

    test "chrome: false produces --no-chrome" do
      args = CLI.build_args(prompt: "x", chrome: false)
      assert "--no-chrome" in args
      refute "--chrome" in args
    end

    test "chrome not set omits both --chrome and --no-chrome" do
      args = CLI.build_args(prompt: "x")
      refute "--chrome" in args
      refute "--no-chrome" in args
    end

    test "sandbox: true produces --sandbox" do
      args = CLI.build_args(prompt: "x", sandbox: true)
      assert "--sandbox" in args
    end

    test "sandbox not set omits --sandbox" do
      args = CLI.build_args(prompt: "x")
      refute "--sandbox" in args
    end

    test "permission_mode produces --permission-mode <value>" do
      args = CLI.build_args(prompt: "x", permission_mode: "plan")
      idx = Enum.find_index(args, &(&1 == "--permission-mode"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "plan"
    end

    test "add_dir produces --add-dir <path>" do
      args = CLI.build_args(prompt: "x", add_dir: "/some/path")
      idx = Enum.find_index(args, &(&1 == "--add-dir"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "/some/path"
    end

    test "mcp_config produces --mcp-config <path>" do
      args = CLI.build_args(prompt: "x", mcp_config: "./mcp.json")
      idx = Enum.find_index(args, &(&1 == "--mcp-config"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "./mcp.json"
    end

    test "plugin_dir produces --plugin-dir <path>" do
      args = CLI.build_args(prompt: "x", plugin_dir: "./plugins")
      idx = Enum.find_index(args, &(&1 == "--plugin-dir"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "./plugins"
    end

    test "settings_file produces --settings <path>" do
      args = CLI.build_args(prompt: "x", settings_file: "./settings.json")
      idx = Enum.find_index(args, &(&1 == "--settings"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "./settings.json"
    end

    test "all advanced flags together" do
      args =
        CLI.build_args(
          prompt: "x",
          chrome: true,
          sandbox: true,
          permission_mode: "acceptEdits",
          add_dir: "/lib",
          mcp_config: "./mcp.json",
          plugin_dir: "./plugins",
          settings_file: "./settings.json",
          max_turns: 10
        )

      assert "--chrome" in args
      assert "--sandbox" in args
      assert "--permission-mode" in args
      assert "acceptEdits" in args
      assert "--add-dir" in args
      assert "/lib" in args
      assert "--mcp-config" in args
      assert "--plugin-dir" in args
      assert "--settings" in args
      assert "--max-turns" in args
    end
  end

  describe "content_blocks_json/1" do
    test "returns nil when no content_blocks" do
      assert CLI.content_blocks_json(prompt: "hello") == nil
    end

    test "returns nil for empty content_blocks" do
      assert CLI.content_blocks_json(prompt: "hello", content_blocks: []) == nil
    end

    test "returns JSON user message with text and image blocks" do
      blocks = [
        %{
          "type" => "image",
          "source" => %{"type" => "base64", "media_type" => "image/png", "data" => "iVBOR"}
        }
      ]

      json = CLI.content_blocks_json(prompt: "describe this", content_blocks: blocks)

      assert json != nil
      decoded = Jason.decode!(json)
      assert decoded["type"] == "user"
      assert length(decoded["content"]) == 2
      assert hd(decoded["content"])["type"] == "text"
      assert hd(decoded["content"])["text"] == "describe this"
      assert List.last(decoded["content"])["type"] == "image"
    end
  end
end
