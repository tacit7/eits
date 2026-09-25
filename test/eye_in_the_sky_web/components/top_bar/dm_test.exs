defmodule EyeInTheSkyWeb.TopBar.DMTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.TopBar.DM

  test "keeps the overflow actions hidden until the menu is active" do
    html = render_component(&DM.toolbar/1, %{})
    document = LazyHTML.from_fragment(html)

    menu = LazyHTML.query_by_id(document, "dm-topbar-relative-menu")
    wrapper = LazyHTML.parent_node(menu)

    assert "eits-dropdown" in LazyHTML.attribute(wrapper, "class"),
           "the top-bar overflow wrapper must use the closed-by-default dropdown primitive"
  end
end
