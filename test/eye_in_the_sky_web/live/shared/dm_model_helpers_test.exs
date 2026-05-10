defmodule EyeInTheSkyWeb.Live.Shared.DmModelHelpersTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.Factory
  alias EyeInTheSkyWeb.Live.Shared.DmModelHelpers

  defp build_socket(assigns) do
    base = %{
      __changed__: %{},
      active_overlay: nil,
      thinking_enabled: false,
      show_live_stream: false,
      selected_model: "claude-sonnet-4-5",
      selected_effort: "",
      max_budget_usd: nil,
      flash: %{}
    }

    %Phoenix.LiveView.Socket{assigns: Map.merge(base, assigns)}
  end

  describe "handle_toggle_model_menu/1" do
    test "opens model_menu when no overlay is active" do
      socket = build_socket(%{active_overlay: nil})
      {:noreply, result} = DmModelHelpers.handle_toggle_model_menu(socket)
      assert result.assigns.active_overlay == :model_menu
    end

    test "closes model_menu when model_menu is already active" do
      socket = build_socket(%{active_overlay: :model_menu})
      {:noreply, result} = DmModelHelpers.handle_toggle_model_menu(socket)
      assert result.assigns.active_overlay == nil
    end

    test "switches to model_menu when a different overlay is active" do
      socket = build_socket(%{active_overlay: :effort_menu})
      {:noreply, result} = DmModelHelpers.handle_toggle_model_menu(socket)
      assert result.assigns.active_overlay == :model_menu
    end
  end

  describe "handle_toggle_effort_menu/1" do
    test "opens effort_menu when no overlay is active" do
      socket = build_socket(%{active_overlay: nil})
      {:noreply, result} = DmModelHelpers.handle_toggle_effort_menu(socket)
      assert result.assigns.active_overlay == :effort_menu
    end

    test "closes effort_menu when effort_menu is already active" do
      socket = build_socket(%{active_overlay: :effort_menu})
      {:noreply, result} = DmModelHelpers.handle_toggle_effort_menu(socket)
      assert result.assigns.active_overlay == nil
    end

    test "switches to effort_menu when a different overlay is active" do
      socket = build_socket(%{active_overlay: :model_menu})
      {:noreply, result} = DmModelHelpers.handle_toggle_effort_menu(socket)
      assert result.assigns.active_overlay == :effort_menu
    end
  end

  describe "handle_toggle_thinking/1" do
    test "enables thinking when it is off" do
      socket = build_socket(%{thinking_enabled: false})
      {:noreply, result} = DmModelHelpers.handle_toggle_thinking(socket)
      assert result.assigns.thinking_enabled == true
    end

    test "disables thinking when it is on" do
      socket = build_socket(%{thinking_enabled: true})
      {:noreply, result} = DmModelHelpers.handle_toggle_thinking(socket)
      assert result.assigns.thinking_enabled == false
    end
  end

  describe "handle_toggle_live_stream/2" do
    test "enables live stream when params explicitly set enabled true (boolean)" do
      socket = build_socket(%{show_live_stream: false})
      {:noreply, result} = DmModelHelpers.handle_toggle_live_stream(%{"enabled" => true}, socket)
      assert result.assigns.show_live_stream == true
    end

    test "enables live stream when params explicitly set enabled true (string)" do
      socket = build_socket(%{show_live_stream: false})

      {:noreply, result} =
        DmModelHelpers.handle_toggle_live_stream(%{"enabled" => "true"}, socket)

      assert result.assigns.show_live_stream == true
    end

    test "toggles live stream off when enabled key is absent" do
      socket = build_socket(%{show_live_stream: true})
      {:noreply, result} = DmModelHelpers.handle_toggle_live_stream(%{}, socket)
      assert result.assigns.show_live_stream == false
    end

    test "toggles live stream on when enabled key is absent and stream is off" do
      socket = build_socket(%{show_live_stream: false})
      {:noreply, result} = DmModelHelpers.handle_toggle_live_stream(%{}, socket)
      assert result.assigns.show_live_stream == true
    end
  end

  describe "handle_select_model/2 — happy path" do
    test "updates selected_model and clears active_overlay on success" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      socket = build_socket(%{session: session, active_overlay: :model_menu})

      {:noreply, result} =
        DmModelHelpers.handle_select_model(
          %{"model" => "claude-haiku-4-5", "effort" => ""},
          socket
        )

      assert result.assigns.selected_model == "claude-haiku-4-5"
      assert result.assigns.active_overlay == nil
    end

    test "preserves supplied effort when model is not opus" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      socket = build_socket(%{session: session, active_overlay: nil})

      {:noreply, result} =
        DmModelHelpers.handle_select_model(
          %{"model" => "claude-sonnet-4-5", "effort" => "high"},
          socket
        )

      assert result.assigns.selected_effort == "high"
    end

    test "defaults effort to medium for claude-opus model with empty effort" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      socket = build_socket(%{session: session, active_overlay: nil})

      {:noreply, result} =
        DmModelHelpers.handle_select_model(
          %{"model" => "claude-opus-4-5", "effort" => ""},
          socket
        )

      assert result.assigns.selected_effort == "medium"
    end

    test "defaults effort to medium for opus shorthand alias" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      socket = build_socket(%{session: session, active_overlay: nil})

      {:noreply, result} =
        DmModelHelpers.handle_select_model(
          %{"model" => "opus", "effort" => ""},
          socket
        )

      assert result.assigns.selected_effort == "medium"
    end

    test "defaults effort to medium for opus[1m] alias" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      socket = build_socket(%{session: session, active_overlay: nil})

      {:noreply, result} =
        DmModelHelpers.handle_select_model(
          %{"model" => "opus[1m]", "effort" => ""},
          socket
        )

      assert result.assigns.selected_effort == "medium"
    end

    test "does not force medium effort when opus model already has explicit effort" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)
      socket = build_socket(%{session: session, active_overlay: nil})

      {:noreply, result} =
        DmModelHelpers.handle_select_model(
          %{"model" => "claude-opus-4-5", "effort" => "high"},
          socket
        )

      assert result.assigns.selected_effort == "high"
    end
  end

  describe "handle_select_effort/2" do
    test "updates selected_effort and clears active_overlay" do
      socket = build_socket(%{selected_effort: "low", active_overlay: :effort_menu})

      {:noreply, result} =
        DmModelHelpers.handle_select_effort(%{"effort" => "high"}, socket)

      assert result.assigns.selected_effort == "high"
      assert result.assigns.active_overlay == nil
    end
  end

  describe "handle_set_max_budget/2" do
    test "parses a valid positive float and assigns it" do
      socket = build_socket(%{max_budget_usd: nil})

      {:noreply, result} =
        DmModelHelpers.handle_set_max_budget(%{"value" => "1.50"}, socket)

      assert result.assigns.max_budget_usd == 1.5
    end

    test "sets nil for zero value" do
      socket = build_socket(%{max_budget_usd: 5.0})
      {:noreply, result} = DmModelHelpers.handle_set_max_budget(%{"value" => "0"}, socket)
      assert result.assigns.max_budget_usd == nil
    end

    test "sets nil for a negative value" do
      socket = build_socket(%{max_budget_usd: 5.0})
      {:noreply, result} = DmModelHelpers.handle_set_max_budget(%{"value" => "-1.0"}, socket)
      assert result.assigns.max_budget_usd == nil
    end

    test "sets nil for non-numeric input" do
      socket = build_socket(%{max_budget_usd: 5.0})
      {:noreply, result} = DmModelHelpers.handle_set_max_budget(%{"value" => "abc"}, socket)
      assert result.assigns.max_budget_usd == nil
    end

    test "sets nil for empty string" do
      socket = build_socket(%{max_budget_usd: 5.0})
      {:noreply, result} = DmModelHelpers.handle_set_max_budget(%{"value" => ""}, socket)
      assert result.assigns.max_budget_usd == nil
    end
  end
end
