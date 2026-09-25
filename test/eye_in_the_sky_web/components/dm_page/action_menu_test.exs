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
end
