defmodule EyeInTheSkyWeb.OverviewLive.Settings.PricingTabTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.OverviewLive.Settings.PricingTab

  defp render_tab(settings \\ %{}) do
    render_component(&PricingTab.render/1, %{settings: settings})
  end

  describe "render/1 - structure" do
    test "renders Token Pricing heading" do
      html = render_tab()
      assert html =~ "Token Pricing"
    end

    test "renders cost description" do
      html = render_tab()
      assert html =~ "Cost per 1M tokens"
    end

    test "renders Reset All button with phx-click" do
      html = render_tab()
      assert html =~ "Reset All"
      assert html =~ ~s(phx-click="reset_pricing")
    end

    test "renders form with phx-change and debounce" do
      html = render_tab()
      assert html =~ ~s(phx-change="save_pricing")
      assert html =~ ~s(phx-debounce="500")
    end

    test "renders within a card element" do
      html = render_tab()
      assert html =~ "card"
      assert html =~ "bg-base-100"
    end
  end

  describe "render/1 - model rows" do
    test "renders all three model names" do
      html = render_tab()
      assert html =~ "opus"
      assert html =~ "sonnet"
      assert html =~ "haiku"
    end

    test "renders table column headers" do
      html = render_tab()
      assert html =~ "Model"
      assert html =~ "Input"
      assert html =~ "Output"
      assert html =~ "Cache Read"
      assert html =~ "Cache Create"
    end
  end

  describe "render/1 - input fields" do
    test "renders input fields named for opus pricing" do
      html = render_tab()
      assert html =~ "pricing_opus_input"
      assert html =~ "pricing_opus_output"
      assert html =~ "pricing_opus_cache_read"
      assert html =~ "pricing_opus_cache_creation"
    end

    test "renders input fields named for sonnet pricing" do
      html = render_tab()
      assert html =~ "pricing_sonnet_input"
      assert html =~ "pricing_sonnet_output"
    end

    test "renders input fields named for haiku pricing" do
      html = render_tab()
      assert html =~ "pricing_haiku_input"
      assert html =~ "pricing_haiku_cache_read"
    end

    test "all inputs use type=number with step and min" do
      html = render_tab()
      assert html =~ ~s(type="number")
      assert html =~ ~s(step="0.01")
      assert html =~ ~s(min="0")
    end
  end

  describe "render/1 - settings values" do
    test "displays pricing values from settings map" do
      html =
        render_tab(%{
          "pricing_opus_input" => "15.00",
          "pricing_opus_output" => "75.00",
          "pricing_sonnet_input" => "3.00",
          "pricing_haiku_output" => "4.00"
        })

      assert html =~ "15.00"
      assert html =~ "75.00"
      assert html =~ "3.00"
      assert html =~ "4.00"
    end

    test "renders with empty settings without crashing" do
      html = render_tab(%{})
      assert is_binary(html)
      assert String.length(html) > 0
    end

    test "renders nil value inputs without crashing" do
      # Settings keys missing → value is nil → rendered as empty value attr
      html = render_tab(%{"pricing_opus_input" => nil})
      assert html =~ "pricing_opus_input"
    end
  end
end
