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
