defmodule EyeInTheSkyWeb.OverviewLive.Settings.PricingTabTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.OverviewLive.Settings.PricingTab

  describe "render/1" do
    test "renders pricing section with heading" do
      assigns = %{
        settings: %{},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(PricingTab, assigns)

      assert html =~ "Token Pricing"
      assert html =~ "Cost per 1M tokens"
    end

    test "renders reset button" do
      assigns = %{
        settings: %{},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(PricingTab, assigns)

      assert html =~ "Reset All"
      assert html =~ "phx-click=\"reset_pricing\""
    end

    test "renders table with model names" do
      assigns = %{
        settings: %{},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(PricingTab, assigns)

      assert html =~ "opus"
      assert html =~ "sonnet"
      assert html =~ "haiku"
    end

    test "renders pricing input fields with correct names" do
      assigns = %{
        settings: %{},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(PricingTab, assigns)

      # Check for input field naming patterns
      assert html =~ "pricing_opus_input"
      assert html =~ "pricing_opus_output"
      assert html =~ "pricing_sonnet_input"
      assert html =~ "pricing_haiku_cache_read"
    end

    test "renders form with phx-change for debounced saving" do
      assigns = %{
        settings: %{},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(PricingTab, assigns)

      assert html =~ "phx-change=\"save_pricing\""
      assert html =~ "phx-debounce=\"500\""
    end

    test "displays pricing values from settings" do
      assigns = %{
        settings: %{
          "pricing_opus_input" => "15.00",
          "pricing_opus_output" => "75.00",
          "pricing_sonnet_input" => "3.00",
          "pricing_sonnet_output" => "15.00",
          "pricing_haiku_input" => "0.80",
          "pricing_haiku_output" => "4.00"
        },
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(PricingTab, assigns)

      assert html =~ "15.00"
      assert html =~ "75.00"
      assert html =~ "3.00"
      assert html =~ "0.80"
    end

    test "renders table headers for pricing columns" do
      assigns = %{
        settings: %{},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(PricingTab, assigns)

      assert html =~ "Model"
      assert html =~ "Input"
      assert html =~ "Output"
      assert html =~ "Cache Read"
      assert html =~ "Cache Create"
    end

    test "renders input fields with type number and step 0.01" do
      assigns = %{
        settings: %{},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(PricingTab, assigns)

      # Count type="number" and step="0.01" occurrences
      # There should be 12 input fields (3 models × 4 pricing types)
      count = String.split(html, ~r/type="number"/) |> length()

      assert count >= 12 # At least 12 number inputs (one per pricing field)
      assert html =~ "step=\"0.01\""
    end

    test "renders inputs with min=0 constraint" do
      assigns = %{
        settings: %{},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(PricingTab, assigns)

      assert html =~ "min=\"0\""
    end

    test "handles empty settings gracefully" do
      assigns = %{
        settings: %{},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      # Should not crash with empty settings
      html = Phoenix.Component.render_to_string(PricingTab, assigns)

      assert is_binary(html)
      assert String.length(html) > 0
    end

    test "renders within a card component" do
      assigns = %{
        settings: %{},
        socket: %Phoenix.LiveView.Socket{assigns: %{}}
      }

      html = Phoenix.Component.render_to_string(PricingTab, assigns)

      assert html =~ "card"
      assert html =~ "bg-base-100"
      assert html =~ "border"
    end
  end
end
