defmodule EyeInTheSkyWeb.Components.ModelSelectorTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.ModelSelector
  alias EyeInTheSky.ModelEntry

  defp claude_entries do
    [
      %ModelEntry{provider: "claude", slug: "claude-opus-4-8", label: "Opus 4.8", group: "Claude Code", default?: true},
      %ModelEntry{provider: "claude", slug: "claude-opus-4-7", label: "Opus 4.7", group: "Claude Code", legacy?: true},
      %ModelEntry{provider: "claude", slug: "opus[1m]", label: "Opus (1M)", group: "Claude Code", premium?: true}
    ]
  end

  test "renders the trigger pill with the current model's display label" do
    html =
      render_component(&ModelSelector.model_selector/1,
        id: "test-selector",
        entries: claude_entries(),
        selected_provider: "claude",
        selected_model: "claude-opus-4-8",
        allow_provider_switch?: false,
        event: "select_model"
      )

    assert html =~ "Opus 4.8"
    assert html =~ ~s(id="test-selector")
  end

  test "renders one row per entry with the checkmark on the active slug" do
    html =
      render_component(&ModelSelector.model_selector/1,
        id: "test-selector",
        entries: claude_entries(),
        selected_provider: "claude",
        selected_model: "claude-opus-4-7",
        allow_provider_switch?: false,
        event: "select_model"
      )

    assert html =~ ~s(data-slug="claude-opus-4-8")
    assert html =~ ~s(data-slug="claude-opus-4-7")
    assert html =~ ~s(data-active="true")
  end

  test "premium entries render a $ marker" do
    html =
      render_component(&ModelSelector.model_selector/1,
        id: "test-selector",
        entries: claude_entries(),
        selected_provider: "claude",
        selected_model: "claude-opus-4-8",
        allow_provider_switch?: false,
        event: "select_model"
      )

    assert html =~ ~s(data-premium="true")
  end

  test "legacy entries are marked for client-side disclosure" do
    html =
      render_component(&ModelSelector.model_selector/1,
        id: "test-selector",
        entries: claude_entries(),
        selected_provider: "claude",
        selected_model: "claude-opus-4-8",
        allow_provider_switch?: false,
        event: "select_model"
      )

    assert html =~ ~s(data-legacy="true")
  end

  test "entries are serialized to the hook's data-models attribute" do
    html =
      render_component(&ModelSelector.model_selector/1,
        id: "test-selector",
        entries: claude_entries(),
        selected_provider: "claude",
        selected_model: "claude-opus-4-8",
        allow_provider_switch?: false,
        event: "select_model"
      )

    assert html =~ "data-models="
    assert html =~ "claude-opus-4-8"
  end

  test "current selection missing from entries is still rendered and checked" do
    html =
      render_component(&ModelSelector.model_selector/1,
        id: "test-selector",
        entries: claude_entries(),
        selected_provider: "claude",
        selected_model: "sonnet-4-6",
        allow_provider_switch?: false,
        event: "select_model"
      )

    assert html =~ ~s(data-slug="sonnet-4-6")
    assert html =~ ~s(data-active="true")
  end

  test "disabled? renders the trigger as a disabled button" do
    html =
      render_component(&ModelSelector.model_selector/1,
        id: "test-selector",
        entries: claude_entries(),
        selected_provider: "claude",
        selected_model: "claude-opus-4-8",
        allow_provider_switch?: false,
        event: "select_model",
        disabled?: true
      )

    assert html =~ "disabled"
  end

  test "myself assign renders phx-target on the hook root" do
    html =
      render_component(&ModelSelector.model_selector/1,
        id: "test-selector",
        entries: claude_entries(),
        selected_provider: "claude",
        selected_model: "claude-opus-4-8",
        allow_provider_switch?: false,
        event: "select_model",
        myself: %Phoenix.LiveComponent.CID{cid: 1}
      )

    assert html =~ ~s(phx-target="1")
  end
end
