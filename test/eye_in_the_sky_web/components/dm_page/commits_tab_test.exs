defmodule EyeInTheSkyWeb.Components.DmPage.CommitsTabTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmPage.CommitsTab

  # Controls (Commits/Full-diff toggle, Unified/Side-by-side toggle) are only
  # rendered when commits is non-empty — the empty-state branch short-circuits.

  defp commit(overrides \\ %{}) do
    Map.merge(
      %{
        id: 1,
        commit_hash: "abc123def456",
        commit_message: "Fix: resolve issue with widget rendering",
        created_at: DateTime.utc_now()
      },
      overrides
    )
  end

  describe "commits_tab/1 — empty state" do
    test "renders empty state when commits list is empty" do
      html =
        render_component(&CommitsTab.commits_tab/1,
          commits: [],
          diff_cache: %{},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "No commits yet"
      assert html =~ "Commits from this session will appear here"
    end
  end

  describe "commits_tab/1 — list view" do
    test "renders commit title" do
      html =
        render_component(&CommitsTab.commits_tab/1,
          commits: [commit()],
          diff_cache: %{},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "Fix: resolve issue with widget rendering"
    end

    test "renders multiple commits" do
      html =
        render_component(&CommitsTab.commits_tab/1,
          commits: [
            commit(%{id: 1, commit_hash: "aaa111", commit_message: "First"}),
            commit(%{id: 2, commit_hash: "bbb222", commit_message: "Second"})
          ],
          diff_cache: %{},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "First"
      assert html =~ "Second"
    end

    test "displays hash truncated to 8 characters in the span" do
      html =
        render_component(&CommitsTab.commits_tab/1,
          commits: [commit(%{commit_hash: "abcdefghijklmnop"})],
          diff_cache: %{},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      # 8-char truncation visible in font-mono span
      assert html =~ ">abcdefgh<"
    end

    test "renders diff viewer when diff_cache has content" do
      c = commit(%{commit_hash: "abc123"})

      html =
        render_component(&CommitsTab.commits_tab/1,
          commits: [c],
          diff_cache: %{"abc123" => "--- a/test.ex\n+++ b/test.ex\n@@ -1 +1 @@\n-old\n+new"},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ ~s(phx-hook="DiffViewer")
    end

    test "renders error message when diff cache entry is :error" do
      c = commit(%{commit_hash: "abc123"})

      html =
        render_component(&CommitsTab.commits_tab/1,
          commits: [c],
          diff_cache: %{"abc123" => :error},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "Could not load diff"
    end

    test "renders view toggle buttons" do
      html =
        render_component(&CommitsTab.commits_tab/1,
          commits: [commit()],
          diff_cache: %{},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "Commits"
      assert html =~ "Full diff"
    end

    test "renders diff mode toggle buttons" do
      html =
        render_component(&CommitsTab.commits_tab/1,
          commits: [commit()],
          diff_cache: %{},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "Unified"
      assert html =~ "Side by side"
    end

    test "commit with nil hash renders without error" do
      html =
        render_component(&CommitsTab.commits_tab/1,
          commits: [commit(%{commit_hash: nil, commit_message: "Nil hash commit"})],
          diff_cache: %{},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "Nil hash commit"
    end
  end

  describe "commits_tab/1 — cumulative diff view" do
    test "renders cumulative diff element" do
      html =
        render_component(&CommitsTab.commits_tab/1,
          commits: [commit()],
          diff_cache: %{},
          commits_view: :cumulative,
          diff_mode: :unified,
          cumulative_diff: "--- a/f.ex\n+++ b/f.ex\n@@ -1 +1 @@"
        )

      assert html =~ "dm-cumulative-diff"
    end

    test "shows loading state when cumulative_diff is nil" do
      html =
        render_component(&CommitsTab.commits_tab/1,
          commits: [commit()],
          diff_cache: %{},
          commits_view: :cumulative,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "Loading full diff"
    end

    test "shows error message when cumulative_diff is :error" do
      html =
        render_component(&CommitsTab.commits_tab/1,
          commits: [commit()],
          diff_cache: %{},
          commits_view: :cumulative,
          diff_mode: :unified,
          cumulative_diff: :error
        )

      assert html =~ "Could not load diff"
    end

    test "renders diff viewer for cumulative diff string" do
      html =
        render_component(&CommitsTab.commits_tab/1,
          commits: [commit()],
          diff_cache: %{},
          commits_view: :cumulative,
          diff_mode: :unified,
          cumulative_diff: "--- a/f.ex\n+++ b/f.ex"
        )

      assert html =~ "dm-cumulative-diff-viewer"
    end
  end
end
