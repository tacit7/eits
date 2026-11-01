defmodule EyeInTheSkyWeb.Components.DmPage.CodexRequestPanelTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias EyeInTheSkyWeb.Components.DmPage.CodexRequestPanel

  test "renders a command approval with its preview and response controls" do
    request = %{
      "id" => "cmd-1",
      "method" => "item/commandExecution/requestApproval",
      "params" => %{
        "reason" => "Needs access",
        "preview" => %{"command" => "git status"}
      }
    }

    html = render_component(&CodexRequestPanel.panel/1, requests: [request])
    document = LazyHTML.from_fragment(html)

    assert LazyHTML.attribute(LazyHTML.query(document, "#codex-requests"), "id") == [
             "codex-requests"
           ]

    assert LazyHTML.attribute(LazyHTML.query(document, "button[value=accept]"), "value") == [
             "accept"
           ]

    assert LazyHTML.attribute(LazyHTML.query(document, "button[value=decline]"), "value") == [
             "decline"
           ]

    assert html =~ "git status"
  end

  test "renders question fields and hides empty request panel" do
    request = %{
      "id" => "ask-1",
      "method" => "tool/requestUserInput",
      "params" => %{"questions" => [%{"id" => "choice", "question" => "Continue?"}]}
    }

    html = render_component(&CodexRequestPanel.panel/1, requests: [request])
    document = LazyHTML.from_fragment(html)

    assert LazyHTML.attribute(
             LazyHTML.query(document, "input[name='approval[answers][choice]']"),
             "name"
           ) == ["approval[answers][choice]"]

    assert LazyHTML.attribute(LazyHTML.query(document, "button[value=answer]"), "value") == [
             "answer"
           ]

    empty = render_component(&CodexRequestPanel.panel/1, requests: [])

    assert LazyHTML.attribute(
             LazyHTML.query(LazyHTML.from_fragment(empty), "#codex-requests"),
             "id"
           ) == []
  end
end
