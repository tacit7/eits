defmodule EyeInTheSkyWeb.Components.DmPage.ActionMenuTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmPage.ActionMenu

  test "wraps the menu in the closed-by-default dropdown primitive" do
    html =
      render_component(&ActionMenu.action_menu/1, %{
        wrapper_id: "dm-actions-menu",
        button_class: "eits-action",
        cancel_btn_id: "dm-cancel-timer-btn"
      })

    document = LazyHTML.from_fragment(html)

    menu_wrapper = LazyHTML.query_by_id(document, "dm-actions-menu")

    assert "eits-dropdown" in LazyHTML.attribute(menu_wrapper, "class"),
           "the dropdown wrapper must hide the action menu until its trigger is active"
  end

  test "anchors the menu panel to the trigger's right edge" do
    html =
      render_component(&ActionMenu.action_menu/1, %{
        wrapper_id: "dm-actions-menu",
        button_class: "eits-action",
        cancel_btn_id: "dm-cancel-timer-btn"
      })

    document = LazyHTML.from_fragment(html)
    menu = LazyHTML.query_by_id(document, "dm-actions-menu-panel")
    menu_class_tokens = class_tokens(menu)

    assert "right-0" in menu_class_tokens,
           "the right-edge menu must expand leftward so its labels remain visible"
  end

  defp class_tokens(element) do
    element
    |> LazyHTML.attribute("class")
    |> Enum.flat_map(&String.split/1)
  end
end
