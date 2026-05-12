defmodule EyeInTheSkyWeb.Components.Rail.Flyout.PromptsSectionTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.Rail.Flyout.PromptsSection

  describe "prompts_filters/1" do
    test "renders search input with placeholder" do
      html =
        render_component(
          &PromptsSection.prompts_filters/1,
          prompt_search: "",
          prompt_scope: "all",
          myself: 1
        )

      assert html =~ "Search prompts"
      assert html =~ "magnifying-glass"
    end

    test "renders search input with current value" do
      html =
        render_component(
          &PromptsSection.prompts_filters/1,
          prompt_search: "system",
          prompt_scope: "all",
          myself: 1
        )

      assert html =~ "value=\"system\""
    end

    test "renders scope pills" do
      html =
        render_component(
          &PromptsSection.prompts_filters/1,
          prompt_search: "",
          prompt_scope: "project",
          myself: 1
        )

      assert html =~ "All"
      assert html =~ "Global"
      assert html =~ "Project"
    end

    test "renders project scope as active" do
      html =
        render_component(
          &PromptsSection.prompts_filters/1,
          prompt_search: "",
          prompt_scope: "project",
          myself: 1
        )

      assert html =~ "bg-primary/15"
    end
  end

  describe "prompts_content/1" do
    test "renders empty message when no prompts" do
      html =
        render_component(
          &PromptsSection.prompts_content/1,
          prompts: [],
          prompt_search: "",
          prompt_scope: "all",
          sidebar_project: nil
        )

      assert html =~ "No prompts"
    end

    test "renders filtered message when no results" do
      html =
        render_component(
          &PromptsSection.prompts_content/1,
          prompts: [],
          prompt_search: "xyz",
          prompt_scope: "all",
          sidebar_project: nil
        )

      assert html =~ "No matching prompts"
    end

    test "renders prompt list" do
      prompts = [
        %{
          id: 1,
          name: "System Prompt",
          slug: "system",
          description: "Main system instructions",
          project_id: nil
        },
        %{id: 2, name: "Custom Prompt", slug: "custom", description: "", project_id: 1}
      ]

      html =
        render_component(
          &PromptsSection.prompts_content/1,
          prompts: prompts,
          prompt_search: "",
          prompt_scope: "all",
          sidebar_project: nil
        )

      assert html =~ "System Prompt"
      assert html =~ "Custom Prompt"
    end
  end
end
