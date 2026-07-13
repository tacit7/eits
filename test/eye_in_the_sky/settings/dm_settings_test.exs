defmodule EyeInTheSky.Settings.DmSettingsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Settings.DmSettings

  @anthropic_full %{
    "anthropic" => %{
      "permission_mode" => "plan",
      "max_turns" => 10,
      "fallback_model" => "haiku",
      "from_pr" => "123",
      "json_schema" => "{\"type\":\"object\"}",
      "allowed_tools" => "Bash,Read",
      "permission_prompt_tool" => "my_tool",
      "add_dir" => "/extra",
      "mcp_config" => "/mcp.json",
      "plugin_dir" => "/plugins",
      "settings_file" => "/settings.json",
      "agents_json" => "{\"agents\":[]}",
      "system_prompt" => "You are helpful.",
      "system_prompt_file" => "/sys.md",
      "append_system_prompt" => "Also be concise.",
      "append_system_prompt_file" => "/append.md",
      "debug_categories" => "tools",
      "bare" => true,
      "verbose" => true,
      "include_partial_messages" => true,
      "no_session_persistence" => true,
      "chrome" => "on",
      "sandbox" => true,
      "dangerously_skip_permissions" => true
    }
  }

  describe "to_provider_opts/2 — Claude provider" do
    test "returns empty list for empty effective map" do
      assert DmSettings.to_provider_opts(%{}, "claude") == []
    end

    test "returns empty list for nil effective map" do
      assert DmSettings.to_provider_opts(nil, "claude") == []
    end

    test "maps permission_mode" do
      effective = %{"anthropic" => %{"permission_mode" => "plan"}}
      opts = DmSettings.to_provider_opts(effective, "claude")
      assert opts[:permission_mode] == "plan"
    end

    test "maps max_turns" do
      effective = %{"anthropic" => %{"max_turns" => 5}}
      opts = DmSettings.to_provider_opts(effective, "claude")
      assert opts[:max_turns] == 5
    end

    test "maps fallback_model" do
      effective = %{"anthropic" => %{"fallback_model" => "haiku"}}
      opts = DmSettings.to_provider_opts(effective, "claude")
      assert opts[:fallback_model] == "haiku"
    end

    test "maps from_pr" do
      effective = %{"anthropic" => %{"from_pr" => "42"}}
      opts = DmSettings.to_provider_opts(effective, "claude")
      assert opts[:from_pr] == "42"
    end

    test "maps allowed_tools" do
      effective = %{"anthropic" => %{"allowed_tools" => "Bash,Read"}}
      opts = DmSettings.to_provider_opts(effective, "claude")
      assert opts[:allowed_tools] == "Bash,Read"
    end

    test "maps add_dir" do
      effective = %{"anthropic" => %{"add_dir" => "/some/path"}}
      opts = DmSettings.to_provider_opts(effective, "claude")
      assert opts[:add_dir] == "/some/path"
    end

    test "maps mcp_config" do
      effective = %{"anthropic" => %{"mcp_config" => "/mcp.json"}}
      opts = DmSettings.to_provider_opts(effective, "claude")
      assert opts[:mcp_config] == "/mcp.json"
    end

    test "maps system_prompt" do
      effective = %{"anthropic" => %{"system_prompt" => "You are a helper."}}
      opts = DmSettings.to_provider_opts(effective, "claude")
      assert opts[:system_prompt] == "You are a helper."
    end

    test "maps debug_categories to :debug" do
      effective = %{"anthropic" => %{"debug_categories" => "tools"}}
      opts = DmSettings.to_provider_opts(effective, "claude")
      assert opts[:debug] == "tools"
    end

    test "maps bare boolean" do
      effective = %{"anthropic" => %{"bare" => true}}
      opts = DmSettings.to_provider_opts(effective, "claude")
      assert opts[:bare] == true
    end

    test "maps sandbox boolean" do
      effective = %{"anthropic" => %{"sandbox" => true}}
      opts = DmSettings.to_provider_opts(effective, "claude")
      assert opts[:sandbox] == true
    end

    test "maps dangerously_skip_permissions to :skip_permissions" do
      effective = %{"anthropic" => %{"dangerously_skip_permissions" => true}}
      opts = DmSettings.to_provider_opts(effective, "claude")
      assert opts[:skip_permissions] == true
    end

    test "maps chrome 'on' to true" do
      effective = %{"anthropic" => %{"chrome" => "on"}}
      opts = DmSettings.to_provider_opts(effective, "claude")
      assert opts[:chrome] == true
    end

    test "maps chrome 'off' to false" do
      effective = %{"anthropic" => %{"chrome" => "off"}}
      opts = DmSettings.to_provider_opts(effective, "claude")
      assert opts[:chrome] == false
    end

    test "does not include nil anthropic values" do
      effective = %{"anthropic" => %{"max_turns" => nil, "permission_mode" => "plan"}}
      opts = DmSettings.to_provider_opts(effective, "claude")
      refute Keyword.has_key?(opts, :max_turns)
      assert opts[:permission_mode] == "plan"
    end

    test "does not include chrome when nil" do
      effective = %{"anthropic" => %{"chrome" => nil}}
      opts = DmSettings.to_provider_opts(effective, "claude")
      refute Keyword.has_key?(opts, :chrome)
    end

    test "full anthropic map produces all expected keys" do
      opts = DmSettings.to_provider_opts(@anthropic_full, "claude")

      assert opts[:permission_mode] == "plan"
      assert opts[:max_turns] == 10
      assert opts[:fallback_model] == "haiku"
      assert opts[:from_pr] == "123"
      assert opts[:allowed_tools] == "Bash,Read"
      assert opts[:add_dir] == "/extra"
      assert opts[:mcp_config] == "/mcp.json"
      assert opts[:plugin_dir] == "/plugins"
      assert opts[:settings_file] == "/settings.json"
      assert opts[:agents_json] == "{\"agents\":[]}"
      assert opts[:system_prompt] == "You are helpful."
      assert opts[:system_prompt_file] == "/sys.md"
      assert opts[:append_system_prompt] == "Also be concise."
      assert opts[:append_system_prompt_file] == "/append.md"
      assert opts[:debug] == "tools"
      assert opts[:bare] == true
      assert opts[:verbose] == true
      assert opts[:include_partial_messages] == true
      assert opts[:no_session_persistence] == true
      assert opts[:chrome] == true
      assert opts[:sandbox] == true
      assert opts[:skip_permissions] == true
    end

    test "does not include openai keys for claude provider" do
      effective = %{
        "anthropic" => %{"permission_mode" => "plan"},
        "openai" => %{"full_auto" => true, "dangerously_bypass_approvals_and_sandbox" => true}
      }

      opts = DmSettings.to_provider_opts(effective, "claude")
      refute Keyword.has_key?(opts, :bypass_sandbox)
      refute Keyword.has_key?(opts, :full_auto)
    end
  end

  describe "to_provider_opts/2 — Codex provider" do
    test "returns empty list for empty effective map" do
      assert DmSettings.to_provider_opts(%{}, "codex") == []
    end

    test "maps full_auto" do
      effective = %{"openai" => %{"full_auto" => true}}
      opts = DmSettings.to_provider_opts(effective, "codex")
      assert opts[:full_auto] == true
    end

    test "maps sandbox and approval policy" do
      effective = %{
        "openai" => %{
          "sandbox" => "read-only",
          "ask_for_approval" => "on-request"
        }
      }

      opts = DmSettings.to_provider_opts(effective, "codex")
      assert opts[:sandbox] == "read-only"
      assert opts[:ask_for_approval] == "on-request"
    end

    test "maps dangerously_bypass_approvals_and_sandbox to :bypass_sandbox" do
      effective = %{"openai" => %{"dangerously_bypass_approvals_and_sandbox" => true}}
      opts = DmSettings.to_provider_opts(effective, "codex")
      assert opts[:bypass_sandbox] == true
    end

    test "maps bypass false explicitly" do
      effective = %{"openai" => %{"dangerously_bypass_approvals_and_sandbox" => false}}
      opts = DmSettings.to_provider_opts(effective, "codex")
      assert Keyword.has_key?(opts, :bypass_sandbox)
      assert opts[:bypass_sandbox] == false
    end

    test "maps full_auto false explicitly" do
      effective = %{"openai" => %{"full_auto" => false}}
      opts = DmSettings.to_provider_opts(effective, "codex")
      assert Keyword.has_key?(opts, :full_auto)
      assert opts[:full_auto] == false
    end

    test "does not include nil openai values" do
      effective = %{"openai" => %{"full_auto" => nil}}
      opts = DmSettings.to_provider_opts(effective, "codex")
      refute Keyword.has_key?(opts, :full_auto)
    end

    test "does not include anthropic keys for codex provider" do
      effective = %{
        "anthropic" => %{"permission_mode" => "plan"},
        "openai" => %{"full_auto" => true}
      }

      opts = DmSettings.to_provider_opts(effective, "codex")
      refute Keyword.has_key?(opts, :permission_mode)
      assert opts[:full_auto] == true
    end
  end

  describe "to_provider_opts/2 — unsupported providers" do
    test "does not apply Claude settings to Pi" do
      effective = %{"anthropic" => %{"permission_mode" => "plan"}}
      assert DmSettings.to_provider_opts(effective, "pi") == []
    end

    test "does not apply Claude settings to unknown providers" do
      effective = %{"anthropic" => %{"permission_mode" => "plan"}}
      assert DmSettings.to_provider_opts(effective, "unknown") == []
    end
  end
end
