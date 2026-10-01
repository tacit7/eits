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

  test "anchors the overflow menu inside the right edge of the viewport" do
    html = render_component(&DM.toolbar/1, %{})
    document = LazyHTML.from_fragment(html)

    menu = LazyHTML.query_by_id(document, "dm-topbar-relative-menu")
    menu_class_tokens = class_tokens(menu)

    assert "right-0" in menu_class_tokens,
           "the right-edge menu must expand leftward so its text remains visible"
  end

  defp class_tokens(element) do
    element
    |> LazyHTML.attribute("class")
    |> Enum.flat_map(&String.split/1)
  end
end
