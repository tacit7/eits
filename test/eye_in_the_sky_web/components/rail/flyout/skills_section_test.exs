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
          myself: self()
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
          myself: self()
        )

      assert html =~ "value=\"test\""
    end

    test "renders scope pills with all options" do
      html =
        render_component(
          &SkillsSection.skills_filters/1,
          skill_search: "",
          skill_scope: "all",
          myself: self()
        )

      assert html =~ "All"
      assert html =~ "Global"
      assert html =~ "Project"
    end

    test "renders correct scope pill as active" do
      html =
        render_component(
          &SkillsSection.skills_filters/1,
          skill_search: "",
          skill_scope: "global",
          myself: self()
        )

      assert html =~ "bg-primary/15"
    end

    test "renders search with debounce" do
      html =
        render_component(
          &SkillsSection.skills_filters/1,
          skill_search: "",
          skill_scope: "all",
          myself: self()
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
          skill_search: "",
          skill_scope: "all"
        )

      assert html =~ "No skills"
    end

    test "renders filtered message when no results" do
      html =
        render_component(
          &SkillsSection.skills_content/1,
          skills: [],
          skill_search: "nonexistent",
          skill_scope: "all"
        )

      assert html =~ "No matching skills"
    end

    test "renders skill list" do
      skills = [
        %{
          id: 1,
          slug: "web-fetch",
          name: "Web Fetch",
          description: "Fetch content from URLs"
        },
        %{
          id: 2,
          slug: "file-edit",
          name: "File Edit",
          description: "Edit files in project"
        }
      ]

      html =
        render_component(
          &SkillsSection.skills_content/1,
          skills: skills,
          skill_search: "",
          skill_scope: "all"
        )

      assert html =~ "Web Fetch"
      assert html =~ "File Edit"
    end

    test "renders skill rows for each skill" do
      skills = [
        %{
          id: 1,
          slug: "skill-1",
          name: "Test Skill",
          description: "Test description"
        }
      ]

      html =
        render_component(
          &SkillsSection.skills_content/1,
          skills: skills,
          skill_search: "",
          skill_scope: "all"
        )

      assert html =~ "Test Skill"
      assert html =~ "Test description"
    end
  end
end
