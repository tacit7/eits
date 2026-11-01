defmodule EyeInTheSkyWeb.Components.MessageComposerTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmPage.MessageComposer

  defp base_assigns(overrides \\ %{}) do
    Map.merge(
      %{
        uploads: %{files: %Phoenix.LiveView.UploadConfig{ref: "test-upload-ref", entries: []}},
        selected_model: "claude-opus-5-5",
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
    assert html =~ "Opus 5.5"
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
        base_assigns(%{provider: "codex", selected_model: "gpt-6-astra"})
      )

    assert html =~ "GPT-6-Astra"
    refute html =~ "gpt-5.2"
    refute html =~ "GPT-5.2"
  end

  test "codex composer replaces stale selected gpt-5.2 with the default option" do
    html =
      render_component(
        &MessageComposer.message_composer/1,
        base_assigns(%{provider: "codex", selected_model: "gpt-5.2"})
      )

    assert html =~ ~s(data-selected-model="gpt-6-astra")
    assert html =~ ~s(id="composer-model-adjustment-notice")
    assert html =~ "gpt-5.2 unavailable"
    refute html =~ "GPT-5.2"
  end

  test "trigger is disabled while processing" do
    html =
      render_component(&MessageComposer.message_composer/1, base_assigns(%{processing: true}))

    assert html =~ "disabled"
  end

  test "Codex controls omit unsupported plan, budget, compact and clear actions" do
    html =
      render_component(
        &MessageComposer.message_composer/1,
        base_assigns(%{
          provider: "codex",
          selected_model: "gpt-6-astra",
          context_used: 143_644,
          context_window: 258_400,
          active_overlay: :context_meter
        })
      )

    document = LazyHTML.from_fragment(html)

    assert LazyHTML.attribute(
             LazyHTML.query(document, "[phx-click='toggle_plan_mode']"),
             "phx-click"
           ) == []

    assert LazyHTML.attribute(LazyHTML.query(document, "[phx-blur='set_max_budget']"), "phx-blur") ==
             []

    assert LazyHTML.attribute(
             LazyHTML.query(document, "[phx-click='send_slash_command']"),
             "phx-click"
           ) == []

    details = LazyHTML.query(document, "[aria-label='Context window details']")
    assert LazyHTML.text(details) =~ "143,644 / 258,400"
    refute LazyHTML.text(details) =~ "Latest files"
    refute LazyHTML.text(details) =~ "System + tools"
  end

  test "composer popovers open above the bottom toolbar" do
    for {overlay, selector} <- [
          {:context_meter, "[aria-label='Context window details']"},
          {:effort_menu, "#reasoning-pill-effort-menu"}
        ] do
      document =
        render_component(
          &MessageComposer.message_composer/1,
          base_assigns(%{
            provider: "codex",
            selected_model: "gpt-6-astra",
            context_used: 143_644,
            context_window: 258_400,
            active_overlay: overlay
          })
        )
        |> LazyHTML.from_fragment()

      classes =
        document
        |> LazyHTML.query(selector)
        |> LazyHTML.attribute("class")
        |> Enum.flat_map(&String.split/1)

      assert "bottom-full" in classes
    end
  end
end
