defmodule EyeInTheSkyWeb.Components.IconsTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  import EyeInTheSkyWeb.Components.Icons

  describe "claude icon" do
    test "renders SVG element" do
      html = render_component(&claude/1, %{})

      assert html =~ "<svg"
      assert html =~ "</svg>"
    end

    test "has correct xmlns attribute" do
      html = render_component(&claude/1, %{})

      assert html =~ ~s(xmlns="http://www.w3.org/2000/svg")
    end

    test "has default class 'size-4'" do
      html = render_component(&claude/1, %{})

      assert html =~ "size-4"
    end

    test "uses custom class when provided" do
      html = render_component(&claude/1, %{class: "size-6 text-primary"})

      assert html =~ "size-6 text-primary"
    end

    test "has fill='currentColor'" do
      html = render_component(&claude/1, %{})

      assert html =~ ~s(fill="currentColor")
    end

    test "has viewBox attribute" do
      html = render_component(&claude/1, %{})

      assert html =~ ~s(viewBox="0 0 16 16")
    end

    test "renders path element" do
      html = render_component(&claude/1, %{})

      assert html =~ "<path"
      assert html =~ "d="
    end

    test "claude logo path is not empty" do
      html = render_component(&claude/1, %{})

      # The SVG should have a substantial path for the Claude logo
      assert html =~ "d=\"m3.127"
    end

    test "respects currentColor for theming" do
      html = render_component(&claude/1, %{})

      assert html =~ "fill=\"currentColor\""
    end

    test "is scalable with size classes" do
      html_small = render_component(&claude/1, %{class: "size-3"})
      html_large = render_component(&claude/1, %{class: "size-8"})

      assert html_small =~ "size-3"
      assert html_large =~ "size-8"
    end

    test "can have additional classes combined" do
      html = render_component(&claude/1, %{class: "size-5 text-success opacity-75"})

      assert html =~ "size-5"
      assert html =~ "text-success"
      assert html =~ "opacity-75"
    end

    test "can be used in different contexts" do
      # Icon alone
      html1 = render_component(&claude/1, %{})
      assert html1 =~ "<svg"

      # Icon with styling
      html2 = render_component(&claude/1, %{class: "text-info"})
      assert html2 =~ "text-info"
    end

    test "preserves SVG structure" do
      html = render_component(&claude/1, %{})

      # Should be valid SVG
      assert html =~ "<svg"
      assert html =~ "<path"
      assert html =~ "</svg>"
    end

    test "matches SVG specification" do
      html = render_component(&claude/1, %{})

      # Required attributes
      assert html =~ "xmlns="
      assert html =~ "viewBox="
      assert html =~ "fill="
    end

    test "class attribute can be empty string" do
      html = render_component(&claude/1, %{class: ""})

      assert html =~ "<svg"
      # Should still render even with empty class
      assert html =~ "viewBox="
    end

    test "default size is appropriate" do
      html = render_component(&claude/1, %{})

      # Default size-4 = w-4 h-4 (1rem)
      assert html =~ "size-4"
    end
  end

  describe "claude icon - svg viewbox" do
    test "viewBox is correct for logo aspect ratio" do
      html = render_component(&claude/1, %{})

      assert html =~ "0 0 16 16"
    end

    test "maintains aspect ratio" do
      # viewBox 0 0 16 16 is 1:1 aspect ratio
      html = render_component(&claude/1, %{})

      assert html =~ "viewBox=\"0 0 16 16\""
    end
  end

  describe "claude icon - integration with components" do
    test "can be wrapped in buttons" do
      # Simulating usage: <button><.claude /></button>
      svg = render_component(&claude/1, %{class: "size-5 mr-2"})

      assert svg =~ "size-5"
      assert svg =~ "mr-2"
    end

    test "works with hover states" do
      svg = render_component(&claude/1, %{class: "hover:text-primary"})

      assert svg =~ "hover:text-primary"
    end

    test "works with conditional display" do
      svg = render_component(&claude/1, %{class: "hidden md:inline"})

      assert svg =~ "hidden"
      assert svg =~ "md:inline"
    end
  end
end
