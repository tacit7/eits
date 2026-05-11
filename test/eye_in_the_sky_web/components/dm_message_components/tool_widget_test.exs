defmodule EyeInTheSkyWeb.Components.DmMessageComponents.ToolWidgetTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmMessageComponents.ToolWidget

  describe "tool_result_body/1" do
    test "renders nothing when body is blank" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "",
          compact: false
        )

      assert html == ""
    end

    test "renders tool card with output content" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "Command output here",
          compact: false
        )

      assert html =~ "Output"
      assert html =~ "Command output here"
      assert html =~ "code-bracket"
    end

    test "renders copy button for non-compact mode" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "Some output",
          compact: false
        )

      assert html =~ "Copy output"
      assert html =~ "clipboard-document"
    end

    test "does not render copy button in compact mode" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "Some output",
          compact: true
        )

      refute html =~ "Copy output"
      refute html =~ "clipboard-document"
    end

    test "renders collapsible details element" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "Output content",
          compact: false
        )

      assert html =~ "<details"
      assert html =~ "</details>"
    end

    test "renders line count for single line" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "single line output",
          compact: true
        )

      assert html =~ "1 line"
    end

    test "renders line count for multiple lines" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "line 1\nline 2\nline 3",
          compact: true
        )

      assert html =~ "3 lines"
    end

    test "renders with whitespace-pre to preserve formatting" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "  indented\n    more indented",
          compact: false
        )

      assert html =~ "whitespace-pre"
    end

    test "renders with overflow-y-auto for long content" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "line 1\nline 2\nline 3\nline 4\nline 5",
          compact: false
        )

      assert html =~ "overflow-y-auto"
    end

    test "renders compact version with smaller styling" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "Compact output",
          compact: true
        )

      assert html =~ "text-micro"
    end

    test "renders non-compact version with standard styling" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "Regular output",
          compact: false
        )

      assert html =~ "text-xs"
    end

    test "handles nil body as blank" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: nil,
          compact: false
        )

      assert html == ""
    end

    test "trims leading and trailing whitespace from body" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "  \n  output text  \n  ",
          compact: false
        )

      assert html =~ "output text"
    end

    test "renders with pre tag for monospace font" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "code output",
          compact: false
        )

      assert html =~ "<pre"
      assert html =~ "font-mono"
    end

    test "renders with code text color variable" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "colored output",
          compact: false
        )

      assert html =~ "code-text"
    end

    test "max height is larger in non-compact mode" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "long\noutput\ntext",
          compact: false
        )

      assert html =~ "max-h-64"
    end

    test "max height is smaller in compact mode" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "long\noutput\ntext",
          compact: true
        )

      assert html =~ "max-h-40"
    end
  end
end
