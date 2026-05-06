defmodule EyeInTheSkyWeb.Live.Shared.SkillsHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Live.Shared.SkillsHelpers
  alias EyeInTheSkyWeb.OverviewLive.Skills.Skill

  defp socket_with(assigns) do
    base = %{
      project: nil,
      type_filter: "all",
      scope_filter: "all",
      search_query: "",
      sort_by: "name_asc",
      skills: [],
      filtered_skills: [],
      __changed__: %{}
    }

    %Phoenix.LiveView.Socket{assigns: Map.merge(base, assigns)}
  end

  defp write_skill(dir, name, body) do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, name), body)
  end

  describe "load_skills/1 with project_path" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "skills-test-#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)

      on_exit(fn -> File.rm_rf!(tmp) end)

      {:ok, tmp: tmp}
    end

    test "loads project skills from project.path, not File.cwd!", %{tmp: tmp} do
      write_skill(Path.join(tmp, ".claude/commands"), "scoped-cmd.md", "scoped command body")

      socket = socket_with(%{project: %{id: 1, path: tmp, name: "test"}})
      socket = SkillsHelpers.load_skills(socket)

      slugs = Enum.map(socket.assigns.skills, & &1.slug)
      assert "scoped-cmd" in slugs
    end

    test "falls back to File.cwd! when project is nil" do
      socket = socket_with(%{project: nil})
      socket = SkillsHelpers.load_skills(socket)

      assert is_list(socket.assigns.skills)
    end

    test "falls back to File.cwd! when project has no path" do
      socket = socket_with(%{project: %{id: 1, path: nil, name: "noop"}})
      socket = SkillsHelpers.load_skills(socket)

      assert is_list(socket.assigns.skills)
    end
  end

  describe "duplicate slugs across sources get distinct ids" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "skills-dup-#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)

      on_exit(fn -> File.rm_rf!(tmp) end)

      {:ok, tmp: tmp}
    end

    test "global command and project command with same slug both load with distinct ids", %{
      tmp: tmp
    } do
      # Project-side command with the same slug as a likely-global one
      write_skill(Path.join(tmp, ".claude/commands"), "clarify.md", "project clarify")

      socket = socket_with(%{project: %{id: 1, path: tmp, name: "x"}})
      socket = SkillsHelpers.load_skills(socket)

      with_slug = Enum.filter(socket.assigns.skills, &(&1.slug == "clarify"))

      # The project clarify must be present and have a distinct id from any global one
      ids = Enum.map(with_slug, & &1.id)
      assert "project_commands:clarify" in ids
      assert Enum.uniq(ids) == ids
    end
  end

  describe "apply_filters_and_sort/2" do
    test "filter_by_type=skills includes both :skills and :project_skills" do
      skills = [
        %Skill{id: "skills:a", slug: "a", source: :skills, description: "", size: 0},
        %Skill{id: "commands:b", slug: "b", source: :commands, description: "", size: 0},
        %Skill{
          id: "project_skills:c",
          slug: "c",
          source: :project_skills,
          description: "",
          size: 0
        },
        %Skill{
          id: "project_commands:d",
          slug: "d",
          source: :project_commands,
          description: "",
          size: 0
        }
      ]

      assigns = %{
        type_filter: "skills",
        scope_filter: "all",
        search_query: "",
        sort_by: "name_asc"
      }

      result = SkillsHelpers.apply_filters_and_sort(skills, assigns)

      assert Enum.map(result, & &1.slug) == ["a", "c"]
    end

    test "filter_by_scope=project includes both project sources" do
      skills = [
        %Skill{id: "skills:a", slug: "a", source: :skills, description: "", size: 0},
        %Skill{
          id: "project_skills:c",
          slug: "c",
          source: :project_skills,
          description: "",
          size: 0
        },
        %Skill{
          id: "project_commands:d",
          slug: "d",
          source: :project_commands,
          description: "",
          size: 0
        }
      ]

      assigns = %{
        type_filter: "all",
        scope_filter: "project",
        search_query: "",
        sort_by: "name_asc"
      }

      result = SkillsHelpers.apply_filters_and_sort(skills, assigns)

      assert Enum.map(result, & &1.slug) == ["c", "d"]
    end

    test "search filters by slug or description (case-insensitive)" do
      skills = [
        %Skill{id: "skills:foo", slug: "foo", source: :skills, description: "Bar baz", size: 0},
        %Skill{id: "skills:zzz", slug: "zzz", source: :skills, description: "nothing", size: 0}
      ]

      assigns = %{
        type_filter: "all",
        scope_filter: "all",
        search_query: "BAZ",
        sort_by: "name_asc"
      }

      result = SkillsHelpers.apply_filters_and_sort(skills, assigns)

      assert Enum.map(result, & &1.slug) == ["foo"]
    end
  end
end
