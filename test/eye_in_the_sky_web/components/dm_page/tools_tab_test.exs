defmodule EyeInTheSkyWeb.Components.DmPage.ToolsTabTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias EyeInTheSkyWeb.Components.DmPage.ToolsTab

  test "Claude init data is labeled as a session-start snapshot" do
    document = render_tools("claude", %{"model" => "claude-test", "tools" => ["Read"]})

    assert LazyHTML.text(LazyHTML.query(document, "#tools-snapshot-label")) =~ "session start"
    assert LazyHTML.text(LazyHTML.query(document, "#dm-tools-tab")) =~ "Read"
  end

  test "Codex does not display Claude init tools" do
    document = render_tools("codex", %{"claude_code_version" => "1.0", "tools" => ["Read"]})
    text = LazyHTML.text(LazyHTML.query(document, "#dm-tools-tab"))

    assert text =~ "Codex tool inventory has not been reported"
    refute text =~ "Claude version"
    refute text =~ "Read"
  end

  test "partial Claude init data and unknown providers render safely" do
    claude = render_tools("claude", %{"model" => "claude-test", "tools" => nil})
    assert LazyHTML.text(LazyHTML.query(claude, "#dm-tools-tab")) =~ "claude-test"

    unknown = render_tools("pi", nil)

    assert LazyHTML.text(LazyHTML.query(unknown, "#dm-tools-tab")) =~
             "Tool inventory has not been reported"
  end

  defp render_tools(provider, data) do
    render_component(&ToolsTab.tools_tab/1, provider: provider, session_init_data: data)
    |> LazyHTML.from_fragment()
  end
end
