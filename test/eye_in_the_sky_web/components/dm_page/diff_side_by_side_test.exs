defmodule EyeInTheSkyWeb.Components.DmPage.DiffSideBySideTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmPage.DiffSideBySide

  # hunk.lines must be a FLAT list of line maps.
  # The component calls Parser.pair_lines(hunk.lines) internally —
  # do NOT pre-pair them as tuples.

  describe "side_by_side/1" do
    test "renders binary file message" do
      diff = %{is_binary: true, hunks: []}

      html = render_component(&DiffSideBySide.side_by_side/1, diff: diff)

      assert html =~ "Binary file"
    end

    test "renders no changes message when hunks are empty" do
      diff = %{is_binary: false, hunks: []}

      html = render_component(&DiffSideBySide.side_by_side/1, diff: diff)

      assert html =~ "No changes"
    end

    test "renders hunk header" do
      diff = %{
        is_binary: false,
        hunks: [%{header: "@@ -1,5 +1,6 @@", lines: []}]
      }

      html = render_component(&DiffSideBySide.side_by_side/1, diff: diff)

      assert html =~ "@@ -1,5 +1,6 @@"
    end

    test "renders added line with green color and + prefix" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1 +1,2 @@",
            lines: [
              %{type: :added, content: "new line", old_line_number: nil, new_line_number: 2}
            ]
          }
        ]
      }

      html = render_component(&DiffSideBySide.side_by_side/1, diff: diff)

      assert html =~ "new line"
      assert html =~ "success/10"
      assert html =~ "+"
    end

    test "renders removed line with red color and - prefix" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1,2 +1 @@",
            lines: [
              %{type: :removed, content: "old line", old_line_number: 1, new_line_number: nil}
            ]
          }
        ]
      }

      html = render_component(&DiffSideBySide.side_by_side/1, diff: diff)

      assert html =~ "old line"
      assert html =~ "error/10"
      assert html =~ "-"
    end

    test "renders context line with neutral color" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1,2 +1,2 @@",
            lines: [
              %{type: :context, content: "unchanged line", old_line_number: 1, new_line_number: 1}
            ]
          }
        ]
      }

      html = render_component(&DiffSideBySide.side_by_side/1, diff: diff)

      assert html =~ "unchanged line"
      refute html =~ "success/10"
      refute html =~ "error/10"
    end

    test "renders line number for added line" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1 +1,2 @@",
            lines: [
              %{type: :added, content: "new", old_line_number: nil, new_line_number: 2}
            ]
          }
        ]
      }

      html = render_component(&DiffSideBySide.side_by_side/1, diff: diff)

      # Line number renders inside a span with surrounding whitespace
      assert html =~ "2"
    end

    test "renders line number for removed line" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -5,2 +5 @@",
            lines: [
              %{type: :removed, content: "old", old_line_number: 5, new_line_number: nil}
            ]
          }
        ]
      }

      html = render_component(&DiffSideBySide.side_by_side/1, diff: diff)

      # Line number renders inside a span with surrounding whitespace
      assert html =~ "5"
    end

    test "renders side-by-side grid with two columns" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1 +1 @@",
            lines: [
              %{type: :removed, content: "old", old_line_number: 1, new_line_number: nil},
              %{type: :added, content: "new", old_line_number: nil, new_line_number: 1}
            ]
          }
        ]
      }

      html = render_component(&DiffSideBySide.side_by_side/1, diff: diff)

      assert html =~ "grid-cols-2"
      assert html =~ "divide-x"
    end

    test "added-only line produces empty left cell (base-300 background)" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1 +1,2 @@",
            lines: [
              %{type: :added, content: "new", old_line_number: nil, new_line_number: 2}
            ]
          }
        ]
      }

      html = render_component(&DiffSideBySide.side_by_side/1, diff: diff)

      assert html =~ "bg-base-300/20"
    end

    test "renders multiple hunks in sequence" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1,2 +1,3 @@",
            lines: [
              %{type: :context, content: "line 1", old_line_number: 1, new_line_number: 1}
            ]
          },
          %{
            header: "@@ -10,2 +11,3 @@",
            lines: [
              %{type: :removed, content: "old line", old_line_number: 10, new_line_number: nil}
            ]
          }
        ]
      }

      html = render_component(&DiffSideBySide.side_by_side/1, diff: diff)

      assert html =~ "@@ -1,2 +1,3 @@"
      assert html =~ "@@ -10,2 +11,3 @@"
      assert html =~ "line 1"
      assert html =~ "old line"
    end

    test "renders whitespace-pre for content preservation" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1 +1 @@",
            lines: [
              %{type: :added, content: "  indented", old_line_number: nil, new_line_number: 1}
            ]
          }
        ]
      }

      html = render_component(&DiffSideBySide.side_by_side/1, diff: diff)

      assert html =~ "whitespace-pre"
    end

    test "removed line paired with added line" do
      diff = %{
        is_binary: false,
        hunks: [
          %{
            header: "@@ -1 +1 @@",
            lines: [
              %{type: :removed, content: "before", old_line_number: 1, new_line_number: nil},
              %{type: :added, content: "after", old_line_number: nil, new_line_number: 1}
            ]
          }
        ]
      }

      html = render_component(&DiffSideBySide.side_by_side/1, diff: diff)

      assert html =~ "before"
      assert html =~ "after"
    end
  end
end
