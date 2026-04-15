defmodule EyeInTheSky.AgentDefinitionsTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.AgentDefinitions
  alias EyeInTheSky.AgentDefinitions.AgentDefinition
  alias EyeInTheSky.Projects

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_project(name \\ "test-project") do
    {:ok, project} =
      Projects.create_project(%{
        id: System.unique_integer([:positive]),
        name: name,
        path: "/tmp/test-project-#{System.unique_integer([:positive])}"
      })

    project
  end

  defp write_agent_file(dir, filename, content) do
    File.mkdir_p!(dir)
    path = Path.join(dir, filename)
    File.write!(path, content)
    path
  end

  defp agent_frontmatter(name, opts \\ []) do
    model = Keyword.get(opts, :model, "sonnet")
    tools = Keyword.get(opts, :tools, nil)

    tools_line =
      case tools do
        nil -> ""
        list when is_list(list) -> "\ntools: #{Enum.join(list, ", ")}"
        str -> "\ntools: #{str}"
      end

    "---\nname: #{name}\ndescription: A test agent#{tools_line}\nmodel: #{model}\n---\nBody content.\n"
  end

  # ---------------------------------------------------------------------------
  # parse_frontmatter/1
  # ---------------------------------------------------------------------------

  describe "parse_frontmatter/1" do
    test "parses inline scalar fields" do
      content = "---\nname: My Agent\ndescription: Does stuff\nmodel: opus\n---\nBody.\n"
      result = AgentDefinitions.parse_frontmatter(content)

      assert result.display_name == "My Agent"
      assert result.description == "Does stuff"
      assert result.model == "opus"
      assert result.tools == []
    end

    test "parses inline comma-separated tools" do
      content = "---\nname: Agent\ntools: Read, Write, Bash\n---\n"
      result = AgentDefinitions.parse_frontmatter(content)

      assert result.tools == ["Read", "Write", "Bash"]
    end

    test "parses YAML list-style tools" do
      content = "---\nname: Agent\ntools:\n  - Read\n  - Write\n  - Bash\n---\n"
      result = AgentDefinitions.parse_frontmatter(content)

      assert result.tools == ["Read", "Write", "Bash"]
    end

    test "returns empty tools when tools field absent" do
      content = "---\nname: Agent\nmodel: sonnet\n---\n"
      result = AgentDefinitions.parse_frontmatter(content)

      assert result.tools == []
    end

    test "returns nil fields when frontmatter absent" do
      result = AgentDefinitions.parse_frontmatter("No frontmatter here.")

      assert result == %{display_name: nil, description: nil, model: nil, tools: []}
    end
  end

  # ---------------------------------------------------------------------------
  # sync_global/0 and sync_project/2
  # ---------------------------------------------------------------------------

  describe "sync_global/0" do
    setup do
      dir =
        System.tmp_dir!() |> Path.join("eits_test_agents_#{System.unique_integer([:positive])}")

      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "syncs definitions from directory", %{dir: dir} do
      write_agent_file(dir, "coder.md", agent_frontmatter("Coder"))
      write_agent_file(dir, "reviewer.md", agent_frontmatter("Reviewer"))

      # Patch the global dir by syncing directly
      AgentDefinitions.sync_directory_for_test(dir, "global", nil)

      defns = Repo.all(AgentDefinition)
      slugs = Enum.map(defns, & &1.slug) |> Enum.sort()

      assert "coder" in slugs
      assert "reviewer" in slugs
    end

    test "marks existing definitions missing when dir is absent" do
      # Create a definition manually
      {:ok, defn} =
        Repo.insert(%AgentDefinition{
          slug: "orphan",
          scope: "global",
          path: "/nonexistent/orphan.md",
          checksum: "abc",
          last_synced_at: DateTime.utc_now()
        })

      assert is_nil(defn.missing_at)

      # Sync a non-existent directory
      AgentDefinitions.sync_directory_for_test("/nonexistent/agents", "global", nil)

      updated = Repo.get!(AgentDefinition, defn.id)
      refute is_nil(updated.missing_at)
    end

    test "marks definitions missing when file is removed", %{dir: dir} do
      write_agent_file(dir, "coder.md", agent_frontmatter("Coder"))
      write_agent_file(dir, "temp.md", agent_frontmatter("Temp"))

      AgentDefinitions.sync_directory_for_test(dir, "global", nil)

      temp_defn =
        Repo.one(from d in AgentDefinition, where: d.slug == "temp" and d.scope == "global")

      assert temp_defn
      assert is_nil(temp_defn.missing_at)

      # Remove temp.md and re-sync
      File.rm!(Path.join(dir, "temp.md"))
      AgentDefinitions.sync_directory_for_test(dir, "global", nil)

      updated = Repo.get!(AgentDefinition, temp_defn.id)
      refute is_nil(updated.missing_at)
    end
  end

  describe "sync_project/2" do
    setup do
      project = create_project()
      dir = System.tmp_dir!() |> Path.join("eits_test_proj_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, project: project, dir: dir}
    end

    test "syncs project-scoped definitions", %{project: project, dir: dir} do
      write_agent_file(dir, "linter.md", agent_frontmatter("Linter"))

      AgentDefinitions.sync_directory_for_test(dir, "project", project.id)

      defn =
        Repo.one(from d in AgentDefinition, where: d.slug == "linter" and d.scope == "project")

      assert defn
      assert defn.project_id == project.id
    end

    test "marks project definitions missing when dir is absent", %{project: project} do
      {:ok, defn} =
        Repo.insert(%AgentDefinition{
          slug: "ghost",
          scope: "project",
          project_id: project.id,
          path: ".claude/agents/ghost.md",
          checksum: "abc",
          last_synced_at: DateTime.utc_now()
        })

      AgentDefinitions.sync_directory_for_test("/nonexistent", "project", project.id)

      updated = Repo.get!(AgentDefinition, defn.id)
      refute is_nil(updated.missing_at)
    end
  end

  # ---------------------------------------------------------------------------
  # resolve/2 — project-over-global precedence
  # ---------------------------------------------------------------------------

  describe "resolve/2" do
    setup do
      project = create_project()

      {:ok, global} =
        Repo.insert(%AgentDefinition{
          slug: "shared",
          scope: "global",
          path: "/global/shared.md",
          checksum: "global_checksum",
          display_name: "Global Shared",
          last_synced_at: DateTime.utc_now()
        })

      {:ok, project_scoped} =
        Repo.insert(%AgentDefinition{
          slug: "shared",
          scope: "project",
          project_id: project.id,
          path: ".claude/agents/shared.md",
          checksum: "project_checksum",
          display_name: "Project Shared",
          last_synced_at: DateTime.utc_now()
        })

      {:ok, project: project, global: global, project_scoped: project_scoped}
    end

    test "returns project-scoped definition when both exist", %{
      project: project,
      project_scoped: ps
    } do
      assert {:ok, defn} = AgentDefinitions.resolve("shared", project.id)
      assert defn.id == ps.id
      assert defn.scope == "project"
    end

    test "falls back to global when no project-scoped definition exists", %{global: global} do
      other_project = create_project("other")

      assert {:ok, defn} = AgentDefinitions.resolve("shared", other_project.id)
      assert defn.id == global.id
      assert defn.scope == "global"
    end

    test "returns not_found when slug does not exist", %{project: project} do
      assert {:error, :not_found} = AgentDefinitions.resolve("nonexistent", project.id)
    end

    test "skips missing definitions", %{project: project, project_scoped: ps, global: global} do
      Repo.update!(AgentDefinition.changeset(ps, %{missing_at: DateTime.utc_now()}))

      assert {:ok, defn} = AgentDefinitions.resolve("shared", project.id)
      assert defn.id == global.id
    end
  end

  # ---------------------------------------------------------------------------
  # resolve_global/1
  # ---------------------------------------------------------------------------

  describe "resolve_global/1" do
    test "returns global definition by slug" do
      {:ok, defn} =
        Repo.insert(%AgentDefinition{
          slug: "my-agent",
          scope: "global",
          path: "/global/my-agent.md",
          checksum: "abc",
          last_synced_at: DateTime.utc_now()
        })

      assert {:ok, found} = AgentDefinitions.resolve_global("my-agent")
      assert found.id == defn.id
    end

    test "returns not_found for missing slug" do
      assert {:error, :not_found} = AgentDefinitions.resolve_global("nope")
    end

    test "skips tombstoned definitions" do
      {:ok, defn} =
        Repo.insert(%AgentDefinition{
          slug: "gone",
          scope: "global",
          path: "/global/gone.md",
          checksum: "abc",
          missing_at: DateTime.utc_now(),
          last_synced_at: DateTime.utc_now()
        })

      assert defn.id
      assert {:error, :not_found} = AgentDefinitions.resolve_global("gone")
    end
  end
end
