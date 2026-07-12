defmodule EyeInTheSkyWeb.Components.DmMessageComponents.ToolRenderingRegressionTest do
  @moduledoc """
  Regression tests for tool widget rendering covering two contract requirements:

  4. Supported output/result stream types must render through the output widget;
     supported call types must render through the call widget. No recognized tool
     event should silently degrade into generic Markdown.
  5. Tool output inside a cluster (compact/flat mode) must expose an accessible
     copy button. The copy button must carry stable data-copy-btn / data-copy-text
     attributes so the global JS handler can find it.

  Tests are written against required behaviour. On the baseline branch (pre-fix)
  those marked EXPECTED FAIL will fail.
  """

  use EyeInTheSkyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmMessageComponents
  alias EyeInTheSkyWeb.Components.DmMessageComponents.ToolWidget

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp msg(opts) do
    %{
      id: Keyword.get(opts, :id, 1),
      sender_role: Keyword.get(opts, :sender_role, "assistant"),
      body: Keyword.get(opts, :body, nil),
      metadata: Keyword.get(opts, :metadata, nil),
      inserted_at: ~U[2026-01-01 00:00:00Z],
      attachments: []
    }
  end

  # ---------------------------------------------------------------------------
  # Contract 4a: stream_type "output" routes to output widget
  # ---------------------------------------------------------------------------

  describe "output stream type routing" do
    test "message_body with stream_type 'output' renders through output widget, not plain Markdown" do
      message = msg(
        body: "some command stdout here",
        metadata: %{"stream_type" => "output"}
      )

      html =
        render_component(
          &DmMessageComponents.message_body/1,
          message: message,
          compact: false,
          flat: false
        )

      # The output widget renders an "Output" label. Plain Markdown rendering
      # would not include it. EXPECTED FAIL on baseline.
      assert html =~ "Output",
             "stream_type='output' must render through the output widget (shows 'Output' label)"
    end

    test "message_body with stream_type 'output' in compact mode renders output widget" do
      message = msg(
        body: "line 1\nline 2",
        metadata: %{"stream_type" => "output"}
      )

      html =
        render_component(
          &DmMessageComponents.message_body/1,
          message: message,
          compact: true,
          flat: true
        )

      # Compact output widget shows line count. Plain Markdown would not.
      assert html =~ "line",
             "compact output stream must show line count via output widget"

      assert html =~ "Output",
             "compact output stream must render 'Output' label; EXPECTED FAIL on baseline"
    end

    test "message_body with stream_type 'tool_result' renders through output widget" do
      message = msg(
        body: "command result",
        metadata: %{"stream_type" => "tool_result"}
      )

      html =
        render_component(
          &DmMessageComponents.message_body/1,
          message: message,
          compact: false,
          flat: false
        )

      # This is the currently-working case — confirm it doesn't regress.
      assert html =~ "Output",
             "stream_type='tool_result' must render through output widget"
    end
  end

  # ---------------------------------------------------------------------------
  # Contract 4b: stream_type "bash" routes to call widget when body is a call
  # ---------------------------------------------------------------------------

  describe "bash stream type routing" do
    test "message_body with stream_type 'bash' and tool-call body renders call widget" do
      message = msg(
        body: ~s(> `Bash` {"command":"echo hello"}),
        metadata: %{"stream_type" => "bash"}
      )

      html =
        render_component(
          &DmMessageComponents.message_body/1,
          message: message,
          compact: false,
          flat: false
        )

      # The call widget renders a collapsible card. If it falls through to plain
      # Markdown the "Bash" tool badge will not appear.
      assert html =~ "Bash",
             "stream_type='bash' with call body must route to call widget"
    end
  end

  # ---------------------------------------------------------------------------
  # Contract 4c: legacy call aliases render call widget, not output widget
  # ---------------------------------------------------------------------------

  describe "tool_use stream type routes to call widget" do
    test "message_body with stream_type 'tool_use' and parsed segments renders call widget" do
      message = msg(
        body: ~s(> `Write` {"file_path":"/tmp/x","content":"hello"}),
        metadata: %{"stream_type" => "tool_use"}
      )

      html =
        render_component(
          &DmMessageComponents.message_body/1,
          message: message,
          compact: false,
          flat: false
        )

      # Call widget shows tool name badge; output widget shows "Output" label.
      assert html =~ "Write",
             "stream_type='tool_use' must route to call widget, not output widget"

      refute html =~ ">Output<" || html =~ ">OUTPUT<",
             "tool_use must NOT fall through to the output widget"
    end
  end

  # ---------------------------------------------------------------------------
  # Contract 5: copy button present in compact/flat mode
  # ---------------------------------------------------------------------------

  describe "copy button accessibility in compact/flat cluster mode" do
    test "tool_result_body in flat mode exposes a copy button with data-copy-btn" do
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "some output text",
          compact: true,
          flat: true
        )

      # The copy button must be reachable in flat/compact mode (cluster rendering).
      # Baseline: tool_card_shell flat branch has no copy button. EXPECTED FAIL.
      assert html =~ "data-copy-btn",
             "tool_result_body in flat=true mode must render a data-copy-btn button"
    end

    test "tool_result_body in flat mode copy button carries data-copy-text" do
      body = "copy this text"

      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: body,
          compact: true,
          flat: true
        )

      # The JS handler reads data-copy-text to know what to write to clipboard.
      # EXPECTED FAIL on baseline (no copy button in flat mode).
      assert html =~ "data-copy-text",
             "copy button must carry data-copy-text attribute in flat mode"
    end

    test "tool_widget in flat mode exposes a copy button" do
      html =
        render_component(
          &ToolWidget.tool_widget/1,
          name: "Bash",
          rest: ~s({"command":"echo hello"}),
          compact: true,
          flat: true
        )

      # Baseline: tool_card_shell flat branch omits copy button. EXPECTED FAIL.
      assert html =~ "data-copy-btn",
             "tool_widget in flat=true mode must render a data-copy-btn button"
    end

    test "tool_widget in flat mode copy button carries data-copy-text with input" do
      rest = ~s({"command":"echo hello"})

      html =
        render_component(
          &ToolWidget.tool_widget/1,
          name: "Bash",
          rest: rest,
          compact: true,
          flat: true
        )

      # EXPECTED FAIL on baseline.
      assert html =~ "data-copy-text",
             "copy button in flat mode must carry data-copy-text"
    end

    test "copy button in non-compact, non-flat mode is present (regression guard)" do
      # This already works on baseline — ensure the fix does not regress it.
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "some output",
          compact: false,
          flat: false
        )

      assert html =~ "data-copy-btn",
             "copy button must remain present in expanded (non-compact, non-flat) mode"
    end

    test "copy button does not appear inside <summary> in flat mode so click can't toggle details" do
      # In flat mode there is no <details>, so the copy button must not be inside
      # a <summary> element (which would toggle the collapsible on click).
      html =
        render_component(
          &ToolWidget.tool_result_body/1,
          body: "output",
          compact: true,
          flat: true
        )

      # Parse out summary block (crude but sufficient: summary appears before the
      # body in the non-flat path; flat path has no summary element at all).
      refute html =~ "<summary",
             "flat mode must not render a <summary> element"
    end
  end
end
