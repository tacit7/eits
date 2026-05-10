defmodule EyeInTheSkyWeb.Live.Shared.PromptsOverlayHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Live.Shared.OverlayHelpers
  alias EyeInTheSkyWeb.Live.Shared.PromptsHelpers

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp prompt(overrides \\ %{}) do
    Map.merge(
      %{
        slug: "my-prompt",
        name: "My Prompt",
        description: "A description",
        project_id: nil,
        updated_at: ~U[2024-01-01 00:00:00Z]
      },
      overrides
    )
  end

  # ---------------------------------------------------------------------------
  # OverlayHelpers.toggle_overlay/2
  # ---------------------------------------------------------------------------

  describe "OverlayHelpers.toggle_overlay/2" do
    test "returns nil when current matches target (closes the overlay)" do
      assert OverlayHelpers.toggle_overlay("settings", "settings") == nil
    end

    test "returns target when current differs (opens a new overlay)" do
      assert OverlayHelpers.toggle_overlay("help", "settings") == "settings"
    end

    test "returns target when current is nil (nothing open yet)" do
      assert OverlayHelpers.toggle_overlay(nil, "settings") == "settings"
    end

    test "returns nil when both arguments are nil" do
      assert OverlayHelpers.toggle_overlay(nil, nil) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # PromptsHelpers.apply_filters_and_sort/2 — scope filter
  # ---------------------------------------------------------------------------

  describe "apply_filters_and_sort/2 — filter_by_scope" do
    setup do
      global = prompt(%{slug: "global-one", name: "Global One", project_id: nil})
      project = prompt(%{slug: "project-one", name: "Project One", project_id: 42})
      {:ok, prompts: [global, project]}
    end

    test "scope 'all' returns every prompt", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{scope_filter: "all"})
      assert length(result) == 2
    end

    test "scope 'global' returns only prompts without a project_id", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{scope_filter: "global"})
      assert length(result) == 1
      assert hd(result).slug == "global-one"
    end

    test "scope 'project' returns only prompts with a project_id", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{scope_filter: "project"})
      assert length(result) == 1
      assert hd(result).slug == "project-one"
    end

    test "unknown scope falls back to returning all prompts", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{scope_filter: "unknown"})
      assert length(result) == 2
    end

    test "missing scope_filter defaults to 'all'", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{})
      assert length(result) == 2
    end
  end

  # ---------------------------------------------------------------------------
  # PromptsHelpers.apply_filters_and_sort/2 — search filter
  # ---------------------------------------------------------------------------

  describe "apply_filters_and_sort/2 — filter_by_search" do
    setup do
      prompts = [
        prompt(%{slug: "alpha-slug", name: "Alpha Name", description: "first desc"}),
        prompt(%{slug: "beta-slug", name: "Beta Name", description: "second desc"}),
        prompt(%{slug: "gamma-slug", name: "Gamma Name", description: "another entry"})
      ]

      {:ok, prompts: prompts}
    end

    test "empty search_query returns all prompts", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{search_query: ""})
      assert length(result) == 3
    end

    test "missing search_query returns all prompts", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{})
      assert length(result) == 3
    end

    test "matches on slug (case-insensitive)", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{search_query: "ALPHA"})
      assert length(result) == 1
      assert hd(result).slug == "alpha-slug"
    end

    test "matches on name (case-insensitive)", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{search_query: "beta name"})
      assert length(result) == 1
      assert hd(result).slug == "beta-slug"
    end

    test "matches on description (case-insensitive)", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{search_query: "ANOTHER"})
      assert length(result) == 1
      assert hd(result).slug == "gamma-slug"
    end

    test "returns empty list when nothing matches", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{search_query: "zzz-no-match"})
      assert result == []
    end

    test "partial slug match returns all matching prompts", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{search_query: "slug"})
      assert length(result) == 3
    end
  end

  # ---------------------------------------------------------------------------
  # PromptsHelpers.apply_filters_and_sort/2 — sorting
  # ---------------------------------------------------------------------------

  describe "apply_filters_and_sort/2 — sort_prompts" do
    setup do
      prompts = [
        prompt(%{slug: "c", name: "Charlie", updated_at: ~U[2024-03-01 00:00:00Z]}),
        prompt(%{slug: "a", name: "Alpha", updated_at: ~U[2024-01-01 00:00:00Z]}),
        prompt(%{slug: "b", name: "Bravo", updated_at: ~U[2024-02-01 00:00:00Z]})
      ]

      {:ok, prompts: prompts}
    end

    test "sort_by 'name_asc' orders alphabetically ascending", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{sort_by: "name_asc"})
      assert Enum.map(result, & &1.name) == ["Alpha", "Bravo", "Charlie"]
    end

    test "sort_by 'name_desc' orders alphabetically descending", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{sort_by: "name_desc"})
      assert Enum.map(result, & &1.name) == ["Charlie", "Bravo", "Alpha"]
    end

    test "sort_by 'recent' orders by updated_at descending (newest first)", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{sort_by: "recent"})
      assert Enum.map(result, & &1.slug) == ["c", "b", "a"]
    end

    test "missing sort_by defaults to 'recent' ordering", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{})
      assert Enum.map(result, & &1.slug) == ["c", "b", "a"]
    end

    test "unknown sort_by falls back to 'recent' ordering", %{prompts: prompts} do
      result = PromptsHelpers.apply_filters_and_sort(prompts, %{sort_by: "not_a_thing"})
      assert Enum.map(result, & &1.slug) == ["c", "b", "a"]
    end
  end

  # ---------------------------------------------------------------------------
  # PromptsHelpers.apply_filters_and_sort/2 — combined filter + sort
  # ---------------------------------------------------------------------------

  describe "apply_filters_and_sort/2 — combined scope + search + sort" do
    test "filters by scope and search, then sorts the result" do
      prompts = [
        prompt(%{
          slug: "global-z",
          name: "Zephyr",
          description: "wind",
          project_id: nil,
          updated_at: ~U[2024-03-01 00:00:00Z]
        }),
        prompt(%{
          slug: "global-a",
          name: "Amber",
          description: "fire",
          project_id: nil,
          updated_at: ~U[2024-01-01 00:00:00Z]
        }),
        prompt(%{
          slug: "project-p",
          name: "Project Prompt",
          description: "work",
          project_id: 1,
          updated_at: ~U[2024-02-01 00:00:00Z]
        })
      ]

      result =
        PromptsHelpers.apply_filters_and_sort(prompts, %{
          scope_filter: "global",
          search_query: "er",
          sort_by: "name_asc"
        })

      # "Zephyr" and "Amber" both contain "er"; project prompt excluded by scope
      assert Enum.map(result, & &1.name) == ["Amber", "Zephyr"]
    end
  end
end
