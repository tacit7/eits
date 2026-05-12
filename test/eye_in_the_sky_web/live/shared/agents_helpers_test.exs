defmodule EyeInTheSkyWeb.Live.Shared.AgentsHelpersTest do
  # File I/O — not touching the DB, so pure ExUnit is fine.
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Live.Shared.AgentsHelpers
  alias EyeInTheSkyWeb.OverviewLive.Agents.AgentDef

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Write a .md agent file into a temp agents directory.
  defp write_agent(dir, slug, content) do
    path = Path.join(dir, "#{slug}.md")
    File.write!(path, content)
    path
  end

  # Build a minimal but valid ~/.claude/agents-shaped directory tree.
  # Returns {global_dir, project_dir} — both are fresh temp dirs.
  defp tmp_agent_dirs(_ctx \\ %{}) do
    id = System.unique_integer([:positive])
    global = Path.join(System.tmp_dir!(), "eits_test_global_#{id}/.claude/agents")
    proj_root = Path.join(System.tmp_dir!(), "eits_test_proj_#{id}")
    proj = Path.join(proj_root, ".claude/agents")
    File.mkdir_p!(global)
    File.mkdir_p!(proj)

    on_exit(fn ->
      File.rm_rf!(Path.dirname(Path.dirname(global)))
      File.rm_rf!(proj_root)
    end)

    {global, proj_root}
  end

  # ---------------------------------------------------------------------------
  # list_agents_for_flyout/1
  # ---------------------------------------------------------------------------

  describe "list_agents_for_flyout/1 with nil (global)" do
    test "returns a list of AgentDef structs" do
      agents = AgentsHelpers.list_agents_for_flyout(nil)

      assert is_list(agents)
      Enum.each(agents, &assert(is_struct(&1, AgentDef)))
    end

    test "caps at 15 entries" do
      agents = AgentsHelpers.list_agents_for_flyout(nil)
      assert length(agents) <= 15
    end

    test "all returned agents have :agents source" do
      agents = AgentsHelpers.list_agents_for_flyout(nil)
      Enum.each(agents, &assert(&1.source == :agents))
    end
  end

  describe "list_agents_for_flyout/1 with project" do
    test "returns :project_agents source agents for a project with a valid path" do
      {_global, proj_root} = tmp_agent_dirs()

      agents = AgentsHelpers.list_agents_for_flyout(%{path: proj_root})

      assert is_list(agents)
      Enum.each(agents, &assert(&1.source == :project_agents))
    end

    test "caps project agents at 15" do
      {_global, proj_root} = tmp_agent_dirs()
      agents = AgentsHelpers.list_agents_for_flyout(%{path: proj_root})
      assert length(agents) <= 15
    end

    test "falls back to global when project path is empty string" do
      agents = AgentsHelpers.list_agents_for_flyout(%{path: ""})
      assert is_list(agents)
      Enum.each(agents, &assert(&1.source == :agents))
    end

    test "falls back to global when project has no :path key" do
      agents = AgentsHelpers.list_agents_for_flyout(%{other: "stuff"})
      assert is_list(agents)
      Enum.each(agents, &assert(&1.source == :agents))
    end
  end

  # ---------------------------------------------------------------------------
  # list_agents_for_flyout_filtered/3 — exercises scope + search filtering
  # ---------------------------------------------------------------------------

  describe "list_agents_for_flyout_filtered/3" do
    setup do
      {_global, proj_root} = tmp_agent_dirs()

      proj_agents_dir = Path.join(proj_root, ".claude/agents")

      # Write all fixtures into the project agents dir — global (~/.claude/agents)
      # is always hardcoded by do_load_agents and we cannot control it in tests.
      write_agent(proj_agents_dir, "search-agent", """
      ---
      name: Search Agent
      description: Finds things fast
      ---
      Content
      """)

      write_agent(proj_agents_dir, "deploy-helper", """
      ---
      name: Deploy Helper
      description: Runs deploys
      ---
      Content
      """)

      write_agent(proj_agents_dir, "project-linter", """
      ---
      name: Project Linter
      description: Lints project code
      ---
      Content
      """)

      {:ok, proj_root: proj_root}
    end

    test "scope 'all' includes project agents", %{proj_root: proj_root} do
      agents = AgentsHelpers.list_agents_for_flyout_filtered(%{path: proj_root}, "", "all")
      sources = Enum.map(agents, & &1.source) |> Enum.uniq()
      # project agents are always present; global may or may not exist on CI
      assert :project_agents in sources
    end

    test "scope 'global' returns only :agents", %{proj_root: proj_root} do
      agents = AgentsHelpers.list_agents_for_flyout_filtered(%{path: proj_root}, "", "global")
      Enum.each(agents, &assert(&1.source == :agents))
    end

    test "scope 'project' returns only :project_agents", %{proj_root: proj_root} do
      agents = AgentsHelpers.list_agents_for_flyout_filtered(%{path: proj_root}, "", "project")
      assert length(agents) >= 3
      Enum.each(agents, &assert(&1.source == :project_agents))
    end

    test "search filters by slug (case-insensitive)", %{proj_root: proj_root} do
      agents =
        AgentsHelpers.list_agents_for_flyout_filtered(%{path: proj_root}, "SEARCH", "project")

      assert Enum.any?(agents, &String.contains?(String.downcase(&1.slug), "search"))

      Enum.each(agents, fn a ->
        match =
          String.contains?(String.downcase(a.slug), "search") or
            String.contains?(String.downcase(a.name || ""), "search") or
            String.contains?(String.downcase(a.description || ""), "search")

        assert match
      end)
    end

    test "search filters by description", %{proj_root: proj_root} do
      agents =
        AgentsHelpers.list_agents_for_flyout_filtered(%{path: proj_root}, "deploys", "project")

      assert Enum.any?(
               agents,
               &String.contains?(String.downcase(&1.description || ""), "deploys")
             )
    end

    test "empty search returns all project agents", %{proj_root: proj_root} do
      all = AgentsHelpers.list_agents_for_flyout_filtered(%{path: proj_root}, "", "project")

      empty =
        AgentsHelpers.list_agents_for_flyout_filtered(
          %{path: proj_root},
          "zzz_no_match_zzz",
          "project"
        )

      assert length(all) > 0
      assert length(empty) == 0
    end

    test "caps at 30 results", %{proj_root: proj_root} do
      agents = AgentsHelpers.list_agents_for_flyout_filtered(%{path: proj_root}, "", "all")
      assert length(agents) <= 30
    end
  end

  # ---------------------------------------------------------------------------
  # apply_filters_and_sort/2 — tests sort + filter combinations
  # ---------------------------------------------------------------------------

  describe "apply_filters_and_sort/2" do
    setup do
      {_global, proj_root} = tmp_agent_dirs()
      proj_agents_dir = Path.join(proj_root, ".claude/agents")

      # Write to proj_agents_dir — do_load_agents hardcodes ~/.claude/agents for
      # global, so temp global dirs are never read. Use project scope instead.
      write_agent(proj_agents_dir, "zebra", """
      ---
      name: Zebra Tool
      description: Last alphabetically
      ---
      """)

      write_agent(proj_agents_dir, "alpha", """
      ---
      name: Alpha Tool
      description: First alphabetically
      ---
      """)

      agents = AgentsHelpers.list_agents_for_flyout_filtered(%{path: proj_root}, "", "project")
      own = Enum.filter(agents, &(&1.slug in ["zebra", "alpha"]))
      {:ok, agents: own}
    end

    test "sort_by 'name' (ascending default)", %{agents: agents} do
      assigns = %{scope_filter: "all", search_query: "", sort_by: "name"}
      sorted = AgentsHelpers.apply_filters_and_sort(agents, assigns)
      names = Enum.map(sorted, & &1.name)
      assert names == Enum.sort(names)
    end

    test "sort_by 'name_desc' reverses name order", %{agents: agents} do
      assigns = %{scope_filter: "all", search_query: "", sort_by: "name_desc"}
      sorted = AgentsHelpers.apply_filters_and_sort(agents, assigns)
      names = Enum.map(sorted, & &1.name)
      assert names == Enum.sort(names, :desc)
    end

    test "search_query filters results", %{agents: agents} do
      assigns = %{scope_filter: "all", search_query: "zebra", sort_by: "name"}
      filtered = AgentsHelpers.apply_filters_and_sort(agents, assigns)
      assert length(filtered) == 1
      assert hd(filtered).slug == "zebra"
    end

    test "non-matching search_query returns empty list", %{agents: agents} do
      assigns = %{scope_filter: "all", search_query: "xyzzy_nomatch", sort_by: "name"}
      assert AgentsHelpers.apply_filters_and_sort(agents, assigns) == []
    end
  end

  # ---------------------------------------------------------------------------
  # Frontmatter parsing — exercised through list_agents_for_flyout_filtered
  # so we test the AgentDef fields it produces, not the private function.
  # ---------------------------------------------------------------------------

  describe "frontmatter parsing via loaded agents" do
    # Write fixtures to proj_root/.claude/agents and use scope "project" so
    # tests are isolated from the developer's real ~/.claude/agents directory.
    setup do
      {_global, proj_root} = tmp_agent_dirs()
      proj_agents_dir = Path.join(proj_root, ".claude/agents")
      {:ok, proj_root: proj_root, proj_agents_dir: proj_agents_dir}
    end

    test "parses name, description, and model from YAML frontmatter",
         %{proj_root: proj_root, proj_agents_dir: dir} do
      write_agent(dir, "full-fm", """
      ---
      name: Full FM Agent
      description: Has all fields
      model: sonnet
      ---
      Body text
      """)

      agents =
        AgentsHelpers.list_agents_for_flyout_filtered(%{path: proj_root}, "full-fm", "project")

      assert [agent] = agents
      assert agent.name == "Full FM Agent"
      assert agent.description == "Has all fields"
      assert agent.model == "sonnet"
    end

    test "parses tools as YAML list", %{proj_root: proj_root, proj_agents_dir: dir} do
      write_agent(dir, "tool-list", """
      ---
      name: Tool Agent
      tools:
        - bash
        - read
        - write
      ---
      """)

      agents =
        AgentsHelpers.list_agents_for_flyout_filtered(%{path: proj_root}, "tool-list", "project")

      assert [agent] = agents
      assert "bash" in agent.tools
      assert "read" in agent.tools
      assert "write" in agent.tools
    end

    test "parses tools as inline list", %{proj_root: proj_root, proj_agents_dir: dir} do
      write_agent(dir, "tool-inline", """
      ---
      name: Inline Tool Agent
      tools: [bash, read]
      ---
      """)

      agents =
        AgentsHelpers.list_agents_for_flyout_filtered(
          %{path: proj_root},
          "tool-inline",
          "project"
        )

      assert [agent] = agents
      assert length(agent.tools) == 2
    end

    test "falls back to first # heading when no frontmatter",
         %{proj_root: proj_root, proj_agents_dir: dir} do
      write_agent(dir, "no-fm", """
      # My Heading Agent

      Just some content without frontmatter.
      """)

      agents =
        AgentsHelpers.list_agents_for_flyout_filtered(%{path: proj_root}, "no-fm", "project")

      assert [agent] = agents
      assert agent.description == "My Heading Agent"
    end

    test "returns 'No description' when no frontmatter and no heading",
         %{proj_root: proj_root, proj_agents_dir: dir} do
      write_agent(dir, "empty-agent", "Just prose, no heading.\n")

      agents =
        AgentsHelpers.list_agents_for_flyout_filtered(
          %{path: proj_root},
          "empty-agent",
          "project"
        )

      assert [agent] = agents
      assert agent.description == "No description"
    end

    test "uses slug as name when frontmatter has no name field",
         %{proj_root: proj_root, proj_agents_dir: dir} do
      write_agent(dir, "no-name-fm", """
      ---
      description: I have no name field
      ---
      Content
      """)

      agents =
        AgentsHelpers.list_agents_for_flyout_filtered(%{path: proj_root}, "no-name-fm", "project")

      assert [agent] = agents
      assert agent.name == "no-name-fm"
    end

    test "skips README.md files", %{proj_root: proj_root, proj_agents_dir: dir} do
      File.write!(Path.join(dir, "README.md"), "# Readme\n\nShould be ignored.")

      all = AgentsHelpers.list_agents_for_flyout_filtered(%{path: proj_root}, "", "project")
      refute Enum.any?(all, &(&1.slug == "README"))
    end

    test "ignores non-.md files", %{proj_root: proj_root, proj_agents_dir: dir} do
      File.write!(Path.join(dir, "script.sh"), "#!/bin/bash\necho hi")

      all = AgentsHelpers.list_agents_for_flyout_filtered(%{path: proj_root}, "", "project")
      refute Enum.any?(all, &(&1.slug == "script"))
    end
  end

  # ---------------------------------------------------------------------------
  # handle_search / handle_sort_agents / handle_filter_scope
  # These are thin wrappers that update socket assigns and call a reload fn.
  # ---------------------------------------------------------------------------

  describe "handle_search/3" do
    test "updates search_query assign and calls reload_fn" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, search_query: ""}}
      called = Agent.start_link(fn -> false end) |> elem(1)

      reload_fn = fn s ->
        Agent.update(called, fn _ -> true end)
        s
      end

      {:noreply, updated} = AgentsHelpers.handle_search(%{"query" => "foo"}, socket, reload_fn)

      assert updated.assigns.search_query == "foo"
      assert Agent.get(called, & &1)
      Agent.stop(called)
    end
  end

  describe "handle_sort_agents/3" do
    test "updates sort_by assign and calls reload_fn" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, sort_by: "name"}}

      {:noreply, updated} =
        AgentsHelpers.handle_sort_agents(%{"by" => "name_desc"}, socket, & &1)

      assert updated.assigns.sort_by == "name_desc"
    end
  end

  describe "handle_filter_scope/3" do
    test "updates scope_filter assign and calls reload_fn" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, scope_filter: "all"}}

      {:noreply, updated} =
        AgentsHelpers.handle_filter_scope(%{"scope" => "global"}, socket, & &1)

      assert updated.assigns.scope_filter == "global"
    end
  end
end
