defmodule EyeInTheSkyWeb.Components.DmPage.CommitsTabTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmPage.CommitsTab

  describe "commits_tab/1" do
    test "renders empty state when commits list is empty" do
      html =
        render_component(
          &CommitsTab.commits_tab/1,
          commits: [],
          diff_cache: %{},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "No commits yet"
      assert html =~ "Commits from this session will appear here"
    end

    test "renders commits list when commits are provided" do
      commits = [
        %{
          id: 1,
          commit_hash: "abc123def456",
          commit_message: "Fix: resolve issue with widget rendering",
          created_at: DateTime.utc_now()
        },
        %{
          id: 2,
          commit_hash: "def456ghi789",
          commit_message: "Feat: add new settings panel",
          created_at: DateTime.utc_now()
        }
      ]

      html =
        render_component(
          &CommitsTab.commits_tab/1,
          commits: commits,
          diff_cache: %{},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "Fix: resolve issue with widget rendering"
      assert html =~ "Feat: add new settings panel"
      assert html =~ "abc123de"
      assert html =~ "def456gh"
    end

    test "renders commit hash truncated to 8 characters" do
      commits = [
        %{
          id: 1,
          commit_hash: "abcdefghijklmnop",
          commit_message: "Test commit",
          created_at: DateTime.utc_now()
        }
      ]

      html =
        render_component(
          &CommitsTab.commits_tab/1,
          commits: commits,
          diff_cache: %{},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "abcdefgh"
      refute html =~ "abcdefghij"
    end

    test "renders diff viewer when diff_cache has content" do
      commits = [
        %{
          id: 1,
          commit_hash: "abc123",
          commit_message: "Test",
          created_at: DateTime.utc_now()
        }
      ]

      diff_content = "--- a/test.ex\n+++ b/test.ex\n@@ -1,1 +1,2 @@\n-old line\n+new line"

      html =
        render_component(
          &CommitsTab.commits_tab/1,
          commits: commits,
          diff_cache: %{"abc123" => diff_content},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "phx-hook=\"DiffViewer\""
    end

    test "renders commits and full diff toggle buttons" do
      html =
        render_component(
          &CommitsTab.commits_tab/1,
          commits: [],
          diff_cache: %{},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "Commits"
      assert html =~ "Full diff"
    end

    test "renders unified and side-by-side toggle buttons" do
      html =
        render_component(
          &CommitsTab.commits_tab/1,
          commits: [],
          diff_cache: %{},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "Unified"
      assert html =~ "Side by side"
    end

    test "renders cumulative diff view" do
      cumulative_diff = "--- a/file.ex\n+++ b/file.ex\n@@ -1,2 +1,3 @@"

      html =
        render_component(
          &CommitsTab.commits_tab/1,
          commits: [],
          diff_cache: %{},
          commits_view: :cumulative,
          diff_mode: :unified,
          cumulative_diff: cumulative_diff
        )

      assert html =~ "dm-cumulative-diff"
    end

    test "shows loading spinner for nil cumulative diff" do
      html =
        render_component(
          &CommitsTab.commits_tab/1,
          commits: [],
          diff_cache: %{},
          commits_view: :cumulative,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "Loading full diff"
    end

    test "shows error message for failed diff load" do
      html =
        render_component(
          &CommitsTab.commits_tab/1,
          commits: [],
          diff_cache: %{},
          commits_view: :cumulative,
          diff_mode: :unified,
          cumulative_diff: :error
        )

      assert html =~ "Could not load diff"
    end

    test "renders error message when diff cache value is :error" do
      commits = [
        %{
          id: 1,
          commit_hash: "abc123",
          commit_message: "Test",
          created_at: DateTime.utc_now()
        }
      ]

      html =
        render_component(
          &CommitsTab.commits_tab/1,
          commits: commits,
          diff_cache: %{"abc123" => :error},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "Could not load diff"
    end

    test "commit with nil hash still renders" do
      commits = [
        %{
          id: 1,
          commit_hash: nil,
          commit_message: "Test commit",
          created_at: DateTime.utc_now()
        }
      ]

      html =
        render_component(
          &CommitsTab.commits_tab/1,
          commits: commits,
          diff_cache: %{},
          commits_view: :list,
          diff_mode: :unified,
          cumulative_diff: nil
        )

      assert html =~ "Test commit"
    end
  end
end
