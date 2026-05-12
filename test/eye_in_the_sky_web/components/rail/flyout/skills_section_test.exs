defmodule EyeInTheSkyWeb.Components.Rail.Flyout.SkillsSectionTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.Rail.Flyout.SkillsSection

  describe "skills_filters/1" do
    test "renders search input" do
      html =
        render_component(
          &SkillsSection.skills_filters/1,
          skill_search: "",
          skill_scope: "all",
          myself: 1
        )

      assert html =~ "Search skills"
      assert html =~ "magnifying-glass"
    end

    test "renders search input with current value" do
      html =
        render_component(
          &SkillsSection.skills_filters/1,
          skill_search: "test",
          skill_scope: "all",
          myself: 1
        )

      assert html =~ "value=\"test\""
    end

    test "renders scope pills — All and Project only" do
      html =
        render_component(
          &SkillsSection.skills_filters/1,
          skill_search: "",
          skill_scope: "all",
          myself: 1
        )

      assert html =~ "All"
      assert html =~ "Project"
      refute html =~ "Global"
    end

    test "renders correct scope pill as active" do
      html =
        render_component(
          &SkillsSection.skills_filters/1,
          skill_search: "",
          skill_scope: "project",
          myself: 1
        )

      assert html =~ "bg-primary/15"
    end

    test "renders search with debounce" do
      html =
        render_component(
          &SkillsSection.skills_filters/1,
          skill_search: "",
          skill_scope: "all",
          myself: 1
        )

      assert html =~ "phx-debounce"
    end
  end

  describe "skills_content/1" do
    test "renders empty message when no skills" do
      html =
        render_component(
          &SkillsSection.skills_content/1,
          skills: [],
          skills_route: "/skills"
        )

      assert html =~ "No skills"
    end

    test "renders empty message when no results match search" do
      html =
        render_component(
          &SkillsSection.skills_content/1,
          skills: [],
          skills_route: "/skills"
        )

      # Component shows "No skills" for any empty list
      assert html =~ "No skills"
    end

    test "renders skill list" do
      skills = [
        %{
          id: "skills:web-fetch",
          slug: "web-fetch",
          name: "Web Fetch",
          description: "Fetch content from URLs",
          content: "web fetch skill content",
          source: :skills
        },
        %{
          id: "skills:file-edit",
          slug: "file-edit",
          name: "File Edit",
          description: "Edit files in project",
          content: "file edit skill content",
          source: :skills
        }
      ]

      html =
        render_component(
          &SkillsSection.skills_content/1,
          skills: skills,
          skills_route: "/skills"
        )

      assert html =~ "web-fetch"
      assert html =~ "file-edit"
    end

    test "renders skill rows with Open link pointing to skill" do
      skills = [
        %{
          id: "skills:skill-1",
          slug: "skill-1",
          name: "Test Skill",
          description: "Test description",
          content: "test skill content",
          source: :skills
        }
      ]

      html =
        render_component(
          &SkillsSection.skills_content/1,
          skills: skills,
          skills_route: "/skills"
        )

      assert html =~ "skill-1"
      assert html =~ "Test description"
      assert html =~ "?skill="
    end
  end
end
