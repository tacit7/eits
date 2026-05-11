defmodule EyeInTheSkyWeb.AgentLive.CanvasHandlersTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSkyWeb.AgentLive.CanvasHandlers
  alias EyeInTheSky.Canvases
  alias EyeInTheSky.Factory

  # Build a bare socket with the minimum assigns CanvasHandlers needs.
  defp build_socket do
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, flash: %{}}}
  end

  setup do
    {:ok, canvas} = Canvases.create_canvas(%{name: "Test Canvas"})
    session = Factory.new_session()
    {:ok, canvas: canvas, session: session}
  end

  describe "handle_event show_new_canvas_form" do
    test "assigns show_new_canvas_for with agent id" do
      {:noreply, updated} =
        CanvasHandlers.handle_event("show_new_canvas_form", %{"agent-id" => "123"}, build_socket())

      assert updated.assigns.show_new_canvas_for == "123"
    end

    test "handles different agent IDs" do
      {:noreply, updated} =
        CanvasHandlers.handle_event("show_new_canvas_form", %{"agent-id" => "456"}, build_socket())

      assert updated.assigns.show_new_canvas_for == "456"
    end
  end

  describe "handle_event add_to_canvas" do
    test "adds session to canvas and sets info flash", %{canvas: canvas, session: session} do
      {:noreply, updated} =
        CanvasHandlers.handle_event(
          "add_to_canvas",
          %{"canvas-id" => to_string(canvas.id), "session-id" => to_string(session.id)},
          build_socket()
        )

      assert updated.assigns.flash["info"] =~ canvas.name
    end

    test "sets error flash for nonexistent canvas ID", %{session: session} do
      {:noreply, updated} =
        CanvasHandlers.handle_event(
          "add_to_canvas",
          %{"canvas-id" => "999999", "session-id" => to_string(session.id)},
          build_socket()
        )

      assert updated.assigns.flash["error"]
    end

    test "sets error flash when canvas-id is not a number", %{session: session} do
      {:noreply, updated} =
        CanvasHandlers.handle_event(
          "add_to_canvas",
          %{"canvas-id" => "invalid", "session-id" => to_string(session.id)},
          build_socket()
        )

      assert updated.assigns.flash["error"]
    end

    test "sets error flash when session-id is not a number", %{canvas: canvas} do
      {:noreply, updated} =
        CanvasHandlers.handle_event(
          "add_to_canvas",
          %{"canvas-id" => to_string(canvas.id), "session-id" => "invalid"},
          build_socket()
        )

      assert updated.assigns.flash["error"]
    end

    test "parses string IDs correctly", %{canvas: canvas, session: session} do
      {:noreply, updated} =
        CanvasHandlers.handle_event(
          "add_to_canvas",
          %{"canvas-id" => to_string(canvas.id), "session-id" => to_string(session.id)},
          build_socket()
        )

      # Success path navigates — no error flash
      refute updated.assigns.flash["error"]
    end
  end

  describe "handle_event add_to_new_canvas" do
    test "creates canvas with given name and sets info flash", %{session: session} do
      {:noreply, updated} =
        CanvasHandlers.handle_event(
          "add_to_new_canvas",
          %{"session_id" => to_string(session.id), "canvas_name" => "My Canvas"},
          build_socket()
        )

      assert updated.assigns.flash["info"] =~ "My Canvas"

      canvases = Canvases.list_canvases(limit: 50)
      assert Enum.any?(canvases, &(&1.name == "My Canvas"))
    end

    test "trims whitespace from canvas name", %{session: session} do
      CanvasHandlers.handle_event(
        "add_to_new_canvas",
        %{"session_id" => to_string(session.id), "canvas_name" => "  Trimmed  "},
        build_socket()
      )

      canvases = Canvases.list_canvases(limit: 50)
      assert Enum.any?(canvases, &(&1.name == "Trimmed"))
    end

    test "auto-generates canvas name when name is empty", %{session: session} do
      t_before = :os.system_time(:second)

      CanvasHandlers.handle_event(
        "add_to_new_canvas",
        %{"session_id" => to_string(session.id), "canvas_name" => ""},
        build_socket()
      )

      t_after = :os.system_time(:second)

      canvases = Canvases.list_canvases(limit: 50)

      auto_named =
        Enum.find(canvases, fn c ->
          String.starts_with?(c.name, "Canvas ") &&
            case Integer.parse(String.replace_prefix(c.name, "Canvas ", "")) do
              {ts, ""} -> ts >= t_before && ts <= t_after
              _ -> false
            end
        end)

      assert auto_named, "expected an auto-named canvas between Canvas #{t_before} and Canvas #{t_after}"
    end

    test "auto-generates canvas name when name is nil", %{session: session} do
      CanvasHandlers.handle_event(
        "add_to_new_canvas",
        %{"session_id" => to_string(session.id), "canvas_name" => nil},
        build_socket()
      )

      canvases = Canvases.list_canvases(limit: 50)
      assert Enum.any?(canvases, &String.starts_with?(&1.name, "Canvas "))
    end

    test "returns noreply without crash for invalid session_id" do
      {:noreply, updated} =
        CanvasHandlers.handle_event(
          "add_to_new_canvas",
          %{"session_id" => "invalid", "canvas_name" => "Test"},
          build_socket()
        )

      # parse_int("invalid") == nil → early return, no flash change
      assert updated.assigns.flash == %{}
    end

    test "returns noreply without crash for nil session_id" do
      {:noreply, updated} =
        CanvasHandlers.handle_event(
          "add_to_new_canvas",
          %{"session_id" => nil, "canvas_name" => "Test"},
          build_socket()
        )

      assert updated.assigns.flash == %{}
    end

    test "handles special characters in canvas name", %{session: session} do
      special = "Canvas @#$%^&*() 🎨"

      CanvasHandlers.handle_event(
        "add_to_new_canvas",
        %{"session_id" => to_string(session.id), "canvas_name" => special},
        build_socket()
      )

      canvases = Canvases.list_canvases(limit: 50)
      assert Enum.any?(canvases, &(&1.name == special))
    end
  end
end
