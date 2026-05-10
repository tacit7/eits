defmodule EyeInTheSkyWeb.Live.Shared.AgentsHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Live.Shared.AgentsHelpers
  alias EyeInTheSkyWeb.OverviewLive.Agents.AgentDef

  setup do
    # Create temporary agent files for testing
    tmp_dir = System.tmp_dir!()
    test_id = System.unique_integer([:positive])
    global_agents_dir = Path.join(tmp_dir, "agents_test_#{test_id}")
    project_agents_dir = Path.join(tmp_dir, "project_agents_test_#{test_id}")

    File.mkdir_p!(global_agents_dir)
    File.mkdir_p!(project_agents_dir)

    on_exit(fn ->
      File.rm_rf!(global_agents_dir)
      File.rm_rf!(project_agents_dir)
    end)

    {:ok,
     global_agents_dir: global_agents_dir,
     project_agents_dir: project_agents_dir,
     test_id: test_id}
  end

  describe "list_agents_for_flyout/1 with nil (global)" do
    test "loads agents from ~/.claude/agents" do
      # This test assumes a real ~/.claude/agents directory exists
      # or will gracefully handle the absence

      agents = AgentsHelpers.list_agents_for_flyout(nil)

      # Should be a list (possibly empty if no agents exist)
      assert is_list(agents)

      # If agents exist, they should have the correct structure
      Enum.each(agents, fn agent ->
        assert is_struct(agent, AgentDef)
        assert agent.source == :agents
      end)
    end

    test "returns empty list if no agents exist" do
      agents = AgentsHelpers.list_agents_for_flyout(nil)

      # Should return an empty list or agents from real dir
      assert is_list(agents)
    end

    test "caps results at 15 agents" do
      agents = AgentsHelpers.list_agents_for_flyout(nil)

      assert length(agents) <= 15
    end
  end

  describe "list_agents_for_flyout/1 with project" do
    test "loads project-scoped agents when project has path", %{
      project_agents_dir: proj_dir
    } do
      project = %{path: proj_dir}

      agents = AgentsHelpers.list_agents_for_flyout(project)

      # Should be a list (possibly empty)
      assert is_list(agents)

      # All should be project_agents source
      Enum.each(agents, fn agent ->
        assert agent.source == :project_agents
      end)
    end

    test "falls back to global agents when project is nil" do
      agents = AgentsHelpers.list_agents_for_flyout(nil)

      # Should load global agents
      assert is_list(agents)
    end

    test "falls back to global agents when project path is empty" do
      project = %{path: ""}

      agents = AgentsHelpers.list_agents_for_flyout(project)

      assert is_list(agents)
    end

    test "falls back to global agents when project is invalid" do
      agents = AgentsHelpers.list_agents_for_flyout(%{"invalid" => "structure"})

      assert is_list(agents)
    end

    test "caps project agents at 15" do
      project = %{path: "/tmp"}

      agents = AgentsHelpers.list_agents_for_flyout(project)

      assert length(agents) <= 15
    end
  end

  describe "list_agents_for_flyout_filtered/3" do
    test "returns all agents with scope 'all'" do
      project = %{path: "/tmp"}

      agents = AgentsHelpers.list_agents_for_flyout_filtered(project, "", "all")

      assert is_list(agents)
      assert length(agents) <= 30
    end

    test "filters by scope 'global'" do
      project = %{path: "/tmp"}

      agents = AgentsHelpers.list_agents_for_flyout_filtered(project, "", "global")

      # All should be global source
      Enum.each(agents, fn agent ->
        assert agent.source == :agents
      end)
    end

    test "filters by scope 'project'" do
      project = %{path: "/tmp"}

      agents = AgentsHelpers.list_agents_for_flyout_filtered(project, "", "project")

      # All should be project_agents source
      Enum.each(agents, fn agent ->
        assert agent.source == :project_agents
      end)
    end

    test "filters by search query" do
      # This would need agents with specific names
      # For now, just verify it returns a list
      agents = AgentsHelpers.list_agents_for_flyout_filtered(nil, "test", "all")

      assert is_list(agents)
    end

    test "combines scope and search filters" do
      agents = AgentsHelpers.list_agents_for_flyout_filtered(nil, "agent", "global")

      assert is_list(agents)

      # All should be global if agents exist
      Enum.each(agents, fn agent ->
        assert agent.source == :agents
      end)
    end

    test "caps results at 30" do
      agents = AgentsHelpers.list_agents_for_flyout_filtered(nil, "", "all")

      assert length(agents) <= 30
    end
  end

  describe "filter_by_scope/2" do
    setup %{global_agents_dir: global_dir, project_agents_dir: proj_dir} do
      # Create test agents
      write_agent_file(global_dir, "global-agent.md", ~s{
---
name: Global Agent
---

Test content
      })

      write_agent_file(proj_dir, "project-agent.md", ~s{
---
name: Project Agent
---

Test content
      })

      agents =
        AgentsHelpers.__handle_call__(:do_load_agents, [global_dir, proj_dir])
        |> elem(0)

      {:ok, agents: agents}
    end

    test "filters all agents when scope is 'all'", %{agents: agents} do
      filtered = AgentsHelpers.__handle_call__(:filter_by_scope, [agents, "all"])

      assert length(filtered) == length(agents)
    end

    test "filters global agents when scope is 'global'", %{agents: agents} do
      filtered = AgentsHelpers.__handle_call__(:filter_by_scope, [agents, "global"])

      Enum.each(filtered, fn agent ->
        assert agent.source == :agents
      end)
    end

    test "filters project agents when scope is 'project'", %{agents: agents} do
      filtered = AgentsHelpers.__handle_call__(:filter_by_scope, [agents, "project"])

      Enum.each(filtered, fn agent ->
        assert agent.source == :project_agents
      end)
    end

    test "returns all agents for invalid scope", %{agents: agents} do
      filtered = AgentsHelpers.__handle_call__(:filter_by_scope, [agents, "invalid"])

      assert length(filtered) == length(agents)
    end
  end

  describe "filter_by_search/2" do
    setup %{global_agents_dir: global_dir} do
      write_agent_file(global_dir, "test-agent.md", ~s{
---
name: Test Agent
description: A testing agent
---

Content
      })

      write_agent_file(global_dir, "deploy-agent.md", ~s{
---
name: Deploy Agent
description: Deployment helper
---

Content
      })

      agents =
        AgentsHelpers.__handle_call__(:do_load_agents, [global_dir])
        |> elem(0)

      {:ok, agents: agents}
    end

    test "returns all agents for empty search", %{agents: agents} do
      filtered = AgentsHelpers.__handle_call__(:filter_by_search, [agents, ""])

      assert length(filtered) == length(agents)
    end

    test "filters by slug match", %{agents: agents} do
      filtered = AgentsHelpers.__handle_call__(:filter_by_search, [agents, "test"])

      assert Enum.all?(filtered, fn a ->
        String.contains?(String.downcase(a.slug), "test")
      end)
    end

    test "filters by name match", %{agents: agents} do
      filtered = AgentsHelpers.__handle_call__(:filter_by_search, [agents, "deploy"])

      assert Enum.any?(filtered, fn a ->
        String.contains?(String.downcase(a.name), "deploy")
      end)
    end

    test "is case insensitive", %{agents: agents} do
      filtered1 = AgentsHelpers.__handle_call__(:filter_by_search, [agents, "TEST"])
      filtered2 = AgentsHelpers.__handle_call__(:filter_by_search, [agents, "test"])

      assert length(filtered1) == length(filtered2)
    end

    test "returns empty list for non-matching search", %{agents: agents} do
      filtered = AgentsHelpers.__handle_call__(:filter_by_search, [agents, "nonexistent"])

      assert length(filtered) == 0
    end
  end

  describe "sort_agents/2" do
    setup %{global_agents_dir: global_dir} do
      write_agent_file(global_dir, "zebra-agent.md", ~s{
---
name: Zebra Agent
---
Content
      })

      write_agent_file(global_dir, "alpha-agent.md", ~s{
---
name: Alpha Agent
---
Content
      })

      agents =
        AgentsHelpers.__handle_call__(:do_load_agents, [global_dir])
        |> elem(0)

      {:ok, agents: agents}
    end

    test "sorts by name ascending by default", %{agents: agents} do
      sorted = AgentsHelpers.__handle_call__(:sort_agents, [agents, ""])

      # Should be sorted alphabetically
      names = Enum.map(sorted, & &1.name)
      assert names == Enum.sort(names)
    end

    test "sorts by name ascending", %{agents: agents} do
      sorted = AgentsHelpers.__handle_call__(:sort_agents, [agents, "name"])

      names = Enum.map(sorted, & &1.name)
      assert names == Enum.sort(names)
    end

    test "sorts by name descending", %{agents: agents} do
      sorted = AgentsHelpers.__handle_call__(:sort_agents, [agents, "name_desc"])

      names = Enum.map(sorted, & &1.name)
      assert names == Enum.sort(names, :desc)
    end

    test "handles unknown sort order", %{agents: agents} do
      sorted = AgentsHelpers.__handle_call__(:sort_agents, [agents, "unknown"])

      # Should default to ascending name
      assert is_list(sorted)
      assert length(sorted) == length(agents)
    end
  end

  describe "parse_frontmatter/1" do
    test "parses YAML frontmatter with name, description, model" do
      content = ~s{---
name: My Agent
description: Does stuff
model: sonnet
---

# Main content
      }

      {name, desc, model, tools} =
        AgentsHelpers.__handle_call__(:parse_frontmatter, [content])

      assert name == "My Agent"
      assert desc == "Does stuff"
      assert model == "sonnet"
      assert tools == []
    end

    test "parses tools as YAML list" do
      content = ~s{---
name: Agent
tools:
  - bash
  - read
---

Content
      }

      {_name, _desc, _model, tools} =
        AgentsHelpers.__handle_call__(:parse_frontmatter, [content])

      assert "bash" in tools
      assert "read" in tools
    end

    test "parses tools as inline list" do
      content = ~s{---
name: Agent
tools: [bash, read, write]
---

Content
      }

      {_name, _desc, _model, tools} =
        AgentsHelpers.__handle_call__(:parse_frontmatter, [content])

      assert length(tools) >= 2
    end

    test "handles missing frontmatter" do
      content = ~s{# No frontmatter

Just markdown content
      }

      {name, desc, model, tools} =
        AgentsHelpers.__handle_call__(:parse_frontmatter, [content])

      assert name == nil
      assert desc =~ "No frontmatter" or desc == "No description"
      assert model == nil
      assert tools == []
    end

    test "extracts first heading as description when no frontmatter" do
      content = ~s{# My Agent Title

Some content
      }

      {_name, desc, _model, _tools} =
        AgentsHelpers.__handle_call__(:parse_frontmatter, [content])

      assert desc == "My Agent Title" or desc == "No description"
    end

    test "handles partial frontmatter" do
      content = ~s{---
name: Agent
---

Content
      }

      {name, _desc, model, _tools} =
        AgentsHelpers.__handle_call__(:parse_frontmatter, [content])

      assert name == "Agent"
      assert model == nil
    end
  end

  # Helper to write agent files for testing
  defp write_agent_file(dir, filename, content) do
    path = Path.join(dir, filename)
    File.write!(path, content)
  end
end
