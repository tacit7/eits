defmodule EyeInTheSkyWeb.Components.BookmarkButtonTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  import EyeInTheSkyWeb.Components.BookmarkButton

  describe "bookmark_button - when bookmarked" do
    test "renders with bookmarked state" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: true
        })

      assert html =~ "Bookmarked"
      assert html =~ "Remove bookmark"
    end

    test "renders solid bookmark icon when bookmarked" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: true
        })

      assert html =~ "hero-bookmark-solid"
    end

    test "has correct aria-pressed when bookmarked" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: true
        })

      assert html =~ "aria-pressed=\"true\""
    end

    test "has correct aria-label when bookmarked" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: true
        })

      assert html =~ "aria-label=\"Remove bookmark\""
    end

    test "has title attribute when bookmarked" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: true
        })

      assert html =~ "title=\"Remove bookmark\""
    end

    test "renders warning color class for bookmarked icon" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: true
        })

      assert html =~ "text-warning"
    end
  end

  describe "bookmark_button - when not bookmarked" do
    test "renders with unbookmarked state" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: false
        })

      assert html =~ "Bookmark"
      assert html =~ "Bookmark this file"
    end

    test "renders outline bookmark icon when not bookmarked" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: false
        })

      assert html =~ "hero-bookmark"
      refute html =~ "hero-bookmark-solid"
    end

    test "has correct aria-pressed when not bookmarked" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: false
        })

      assert html =~ "aria-pressed=\"false\""
    end

    test "has correct aria-label when not bookmarked" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: false
        })

      assert html =~ "aria-label=\"Add bookmark\""
    end

    test "has title attribute when not bookmarked" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: false
        })

      assert html =~ "title=\"Bookmark this file\""
    end

    test "has subtle color for unbookmarked icon" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: false
        })

      assert html =~ "text-base-content/40"
    end
  end

  describe "bookmark_button - click event" do
    test "uses default click event" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: false
        })

      assert html =~ "phx-click=\"toggle_bookmark\""
    end

    test "uses custom click event when provided" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: false,
          click_event: "bookmark_file"
        })

      assert html =~ "phx-click=\"bookmark_file\""
    end

    test "custom click event for bookmarked state" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: true,
          click_event: "custom_event"
        })

      assert html =~ "phx-click=\"custom_event\""
    end
  end

  describe "bookmark_button - styling" do
    test "renders button element" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: false
        })

      assert html =~ "<button"
    end

    test "has button styling classes" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: false
        })

      assert html =~ "btn btn-ghost btn-sm gap-2"
    end

    test "has transition classes" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: false
        })

      assert html =~ "transition-colors"
    end

    test "renders icon with correct size" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: false
        })

      assert html =~ "size-5"
    end
  end

  describe "bookmark_button - edge cases" do
    test "renders correctly when is_bookmarked is nil (falsy)" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: nil
        })

      # Should render as not bookmarked since nil is falsy
      assert html =~ "Bookmark"
    end

    test "renders correctly when click_event is empty string" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: false,
          click_event: ""
        })

      assert html =~ "phx-click=\"\""
    end
  end

  describe "bookmark_button - text content" do
    test "renders both icon and text when bookmarked" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: true
        })

      # Should have both icon and text
      assert html =~ "hero-bookmark-solid"
      assert html =~ "Bookmarked"
    end

    test "renders both icon and text when not bookmarked" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: false
        })

      # Should have both icon and text
      assert html =~ "hero-bookmark"
      assert html =~ "Bookmark"
    end

    test "text size is consistent" do
      html_bookmarked =
        render_component(&bookmark_button/1, %{
          is_bookmarked: true
        })

      html_unbookmarked =
        render_component(&bookmark_button/1, %{
          is_bookmarked: false
        })

      assert html_bookmarked =~ "text-sm"
      assert html_unbookmarked =~ "text-sm"
    end
  end

  describe "bookmark_button - accessibility" do
    test "is a proper button element" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: false
        })

      assert html =~ "<button"
      assert html =~ "type=\"button\""
    end

    test "has title attribute for tooltip" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: true
        })

      # title should not be empty
      assert html =~ "title=\""
    end

    test "has aria-pressed attribute" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: true
        })

      assert html =~ "aria-pressed="
    end

    test "has aria-label attribute" do
      html =
        render_component(&bookmark_button/1, %{
          is_bookmarked: true
        })

      assert html =~ "aria-label="
    end
  end
end
