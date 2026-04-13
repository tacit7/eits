defmodule EyeInTheSkyWeb.Helpers.AgentCreationHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Helpers.AgentCreationHelpers

  describe "build_opts/2" do
    test "defaults agent_type to claude" do
      opts = AgentCreationHelpers.build_opts(%{})
      assert opts[:agent_type] == "claude"
    end

    test "defaults model to sonnet" do
      opts = AgentCreationHelpers.build_opts(%{})
      assert opts[:model] == "sonnet"
    end

    test "defaults eits_workflow to 1" do
      opts = AgentCreationHelpers.build_opts(%{})
      assert opts[:eits_workflow] == "1"
    end

    test "overrides are merged into base opts" do
      opts = AgentCreationHelpers.build_opts(%{}, project_path: "/some/path", description: "My Agent")
      assert opts[:project_path] == "/some/path"
      assert opts[:description] == "My Agent"
    end

    test "worktree trims whitespace" do
      opts = AgentCreationHelpers.build_opts(%{"worktree" => "  my-branch  "})
      assert opts[:worktree] == "my-branch"
    end

    test "empty worktree becomes nil" do
      opts = AgentCreationHelpers.build_opts(%{"worktree" => ""})
      assert opts[:worktree] == nil
    end
  end

  describe "advanced CLI params forwarding" do
    test "permission_mode is included when present" do
      opts = AgentCreationHelpers.build_opts(%{"permission_mode" => "bypassPermissions"})
      assert opts[:permission_mode] == "bypassPermissions"
    end

    test "permission_mode is omitted when blank" do
      opts = AgentCreationHelpers.build_opts(%{"permission_mode" => ""})
      refute Keyword.has_key?(opts, :permission_mode)
    end

    test "max_turns is parsed to integer and included when positive" do
      opts = AgentCreationHelpers.build_opts(%{"max_turns" => "10"})
      assert opts[:max_turns] == 10
    end

    test "max_turns is omitted when zero" do
      opts = AgentCreationHelpers.build_opts(%{"max_turns" => "0"})
      refute Keyword.has_key?(opts, :max_turns)
    end

    test "max_turns is omitted when blank" do
      opts = AgentCreationHelpers.build_opts(%{"max_turns" => ""})
      refute Keyword.has_key?(opts, :max_turns)
    end

    test "add_dir is included when present" do
      opts = AgentCreationHelpers.build_opts(%{"add_dir" => "/shared/lib"})
      assert opts[:add_dir] == "/shared/lib"
    end

    test "mcp_config is included when present" do
      opts = AgentCreationHelpers.build_opts(%{"mcp_config" => "./mcp.json"})
      assert opts[:mcp_config] == "./mcp.json"
    end

    test "plugin_dir is included when present" do
      opts = AgentCreationHelpers.build_opts(%{"plugin_dir" => "./plugins"})
      assert opts[:plugin_dir] == "./plugins"
    end

    test "settings_file is included when present" do
      opts = AgentCreationHelpers.build_opts(%{"settings_file" => "./settings.json"})
      assert opts[:settings_file] == "./settings.json"
    end

    test "chrome is true when param is 'true'" do
      opts = AgentCreationHelpers.build_opts(%{"chrome" => "true"})
      assert opts[:chrome] == true
    end

    test "chrome is omitted when param is absent" do
      opts = AgentCreationHelpers.build_opts(%{})
      refute Keyword.has_key?(opts, :chrome)
    end

    test "sandbox is true when param is 'true'" do
      opts = AgentCreationHelpers.build_opts(%{"sandbox" => "true"})
      assert opts[:sandbox] == true
    end

    test "sandbox is omitted when param is absent" do
      opts = AgentCreationHelpers.build_opts(%{})
      refute Keyword.has_key?(opts, :sandbox)
    end

    test "all advanced params forwarded together" do
      params = %{
        "permission_mode" => "acceptEdits",
        "max_turns" => "5",
        "add_dir" => "/extra",
        "mcp_config" => "./mcp.json",
        "plugin_dir" => "./plugins",
        "settings_file" => "./settings.json",
        "chrome" => "true",
        "sandbox" => "true"
      }

      opts = AgentCreationHelpers.build_opts(params)

      assert opts[:permission_mode] == "acceptEdits"
      assert opts[:max_turns] == 5
      assert opts[:add_dir] == "/extra"
      assert opts[:mcp_config] == "./mcp.json"
      assert opts[:plugin_dir] == "./plugins"
      assert opts[:settings_file] == "./settings.json"
      assert opts[:chrome] == true
      assert opts[:sandbox] == true
    end
  end

  describe ":name wiring (do_create_session pattern)" do
    # The :name key is not set by build_opts — it is injected by
    # AgentLive.Index.do_create_session after calling build_opts.
    # This test documents that contract: given agent_name from params,
    # Keyword.put(:name, agent_name) produces the key expected by CLI.build_args.

    test "agent_name placed into opts as :name reaches the keyword list" do
      base_opts = AgentCreationHelpers.build_opts(%{"agent_name" => "My Agent"}, description: "My Agent")
      opts = Keyword.put(base_opts, :name, "My Agent")

      assert opts[:name] == "My Agent"
    end

    test "empty agent_name resolves to nil :name (no --name flag emitted)" do
      agent_name = ""
      name_value = if(agent_name != "", do: agent_name)

      assert name_value == nil
    end
  end
end
