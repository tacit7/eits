defmodule EyeInTheSkyWeb.Components.MessageComposerTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmPage.MessageComposer

  defp base_assigns(overrides \\ %{}) do
    Map.merge(
      %{
        uploads: %{files: %Phoenix.LiveView.UploadConfig{ref: "test-upload-ref", entries: []}},
        selected_model: "claude-opus-4-8",
        selected_effort: "medium",
        active_overlay: nil,
        processing: false,
        slash_items: [],
        thinking_enabled: false,
        show_thinking_blocks: false,
        max_budget_usd: nil,
        provider: "claude",
        context_used: 0,
        context_window: 0,
        total_cost: 0.0,
        display_name: nil,
        session_cli_opts: [],
        session_uuid: "test-uuid"
      },
      overrides
    )
  end

  test "renders the shared model selector scoped to the session's provider" do
    html = render_component(&MessageComposer.message_composer/1, base_assigns())
    assert html =~ ~s(data-event="select_model")
    assert html =~ ~s(data-allow-provider-switch="false")
    assert html =~ "Opus 5"
  end

  test "pi provider sessions get Pi entries, not the Claude fallback (bug being fixed)" do
    html =
      render_component(
        &MessageComposer.message_composer/1,
        base_assigns(%{provider: "pi", selected_model: "ollama-lan/qwen3.6:27b"})
      )

    assert html =~ ~s(data-allow-provider-switch="false")
    # The trigger must not silently fall through to a Claude label.
    refute html =~ "Claude Code"
  end

  test "codex composer does not offer unsupported gpt-5.2" do
    html =
      render_component(
        &MessageComposer.message_composer/1,
        base_assigns(%{provider: "codex", selected_model: "gpt-5.6-sol"})
      )

    assert html =~ "GPT-5.6 Sol"
    refute html =~ "gpt-5.2"
    refute html =~ "GPT-5.2"
  end

  test "codex composer replaces stale selected gpt-5.2 with the default option" do
    html =
      render_component(
        &MessageComposer.message_composer/1,
        base_assigns(%{provider: "codex", selected_model: "gpt-5.2"})
      )

    assert html =~ ~s(data-selected-model="gpt-5.6-sol")
    assert html =~ ~s(id="composer-model-adjustment-notice")
    assert html =~ "gpt-5.2 unavailable"
    refute html =~ "GPT-5.2"
  end

  test "trigger is disabled while processing" do
    html =
      render_component(&MessageComposer.message_composer/1, base_assigns(%{processing: true}))

    assert html =~ "disabled"
  end
end
