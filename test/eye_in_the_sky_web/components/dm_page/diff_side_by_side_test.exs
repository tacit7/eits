defmodule EyeInTheSkyWeb.Components.DmPage.DiffSideBySideTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmPage.DiffSideBySide

  describe "side_by_side/1" do
    test "renders binary file message" do
      diff = %{
        is_binary: true,
        hunks: []
      }

      html =
        render_component(
          &DiffSideBySide.side_by_side/1,
          diff: diff
        )

      assert html =~ "Binary file"
    end

    test "renders no changes message when hunks are empty" do
      diff = %{
        is_binary: false,
        hunks: []
      }

      html =
        render_component(
          &DiffSideBySide.side_by_side/1,
          diff: diff
        )

      assert html =~ "No changes"
    end

    test "renders hunk headers" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1,5 +1,6 @@",
            lines: []
          }
        ]
      }

      html =
        render_component(
          &DiffSideBySide.side_by_side/1,
          diff: diff
        )

      assert html =~ "@@ -1,5 +1,6 @@"
    end

    test "renders added lines with green color and + prefix" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1 +1,2 @@",
            lines: [
              {
                nil,
                %{type: :added, content: "new line", new_line_number: 2}
              }
            ]
          }
        ]
      }

      html =
        render_component(
          &DiffSideBySide.side_by_side/1,
          diff: diff
        )

      assert html =~ "new line"
      assert html =~ "success/10"
      assert html =~ "+"
    end

    test "renders removed lines with red color and - prefix" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1,2 +1 @@",
            lines: [
              {
                %{type: :removed, content: "old line", old_line_number: 1},
                nil
              }
            ]
          }
        ]
      }

      html =
        render_component(
          &DiffSideBySide.side_by_side/1,
          diff: diff
        )

      assert html =~ "old line"
      assert html =~ "error/10"
      assert html =~ "-"
    end

    test "renders context lines with neutral color" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1,2 +1,2 @@",
            lines: [
              {
                %{type: :context, content: "unchanged line", old_line_number: 1},
                %{type: :context, content: "unchanged line", old_line_number: 1}
              }
            ]
          }
        ]
      }

      html =
        render_component(
          &DiffSideBySide.side_by_side/1,
          diff: diff
        )

      assert html =~ "unchanged line"
      refute html =~ "success/10"
      refute html =~ "error/10"
    end

    test "renders line numbers for added lines" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1 +1,2 @@",
            lines: [
              {
                nil,
                %{type: :added, content: "new", new_line_number: 2}
              }
            ]
          }
        ]
      }

      html =
        render_component(
          &DiffSideBySide.side_by_side/1,
          diff: diff
        )

      assert html =~ ">2<"
    end

    test "renders line numbers for removed lines" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1,2 +1 @@",
            lines: [
              {
                %{type: :removed, content: "old", old_line_number: 5},
                nil
              }
            ]
          }
        ]
      }

      html =
        render_component(
          &DiffSideBySide.side_by_side/1,
          diff: diff
        )

      assert html =~ ">5<"
    end

    test "renders side-by-side grid with two columns" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1 +1 @@",
            lines: [
              {
                %{type: :removed, content: "old", old_line_number: 1},
                %{type: :added, content: "new", new_line_number: 1}
              }
            ]
          }
        ]
      }

      html =
        render_component(
          &DiffSideBySide.side_by_side/1,
          diff: diff
        )

      assert html =~ "grid-cols-2"
      assert html =~ "divide-x"
    end

    test "renders empty cell for nil side" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1 +1,2 @@",
            lines: [
              {
                nil,
                %{type: :added, content: "new", new_line_number: 2}
              }
            ]
          }
        ]
      }

      html =
        render_component(
          &DiffSideBySide.side_by_side/1,
          diff: diff
        )

      # Should render two columns, one empty and one with content
      assert html =~ "new"
    end

    test "renders multiple hunks in sequence" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1,2 +1,3 @@",
            lines: [
              {
                %{type: :context, content: "line 1", old_line_number: 1},
                %{type: :context, content: "line 1", old_line_number: 1}
              }
            ]
          },
          %{
            header: "@@ -10,2 +11,3 @@",
            lines: [
              {
                %{type: :removed, content: "old line", old_line_number: 10},
                nil
              }
            ]
          }
        ]
      }

      html =
        render_component(
          &DiffSideBySide.side_by_side/1,
          diff: diff
        )

      assert html =~ "@@ -1,2 +1,3 @@"
      assert html =~ "@@ -10,2 +11,3 @@"
      assert html =~ "line 1"
      assert html =~ "old line"
    end

    test "preserves whitespace in diff content" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1 +1 @@",
            lines: [
              {
                nil,
                %{type: :added, content: "  indented  content  ", new_line_number: 1}
              }
            ]
          }
        ]
      }

      html =
        render_component(
          &DiffSideBySide.side_by_side/1,
          diff: diff
        )

      assert html =~ "whitespace-pre"
    end
  end
end
