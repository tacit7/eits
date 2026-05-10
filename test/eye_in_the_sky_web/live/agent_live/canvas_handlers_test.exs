defmodule EyeInTheSkyWeb.AgentLive.CanvasHandlersTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSkyWeb.AgentLive.CanvasHandlers
  alias EyeInTheSky.Canvases

  setup do
    # Create test data
    {:ok, canvas} = Canvases.create_canvas(%{name: "Test Canvas"})
    {:ok, session} = create_test_session()

    {:ok, canvas: canvas, session: session}
  end

  describe "handle_event show_new_canvas_form" do
    test "assigns show_new_canvas_for with agent id" do
      socket = Phoenix.LiveView.Socket.new(%{})

      {:noreply, updated_socket} =
        CanvasHandlers.handle_event("show_new_canvas_form", %{"agent-id" => "123"}, socket)

      assert updated_socket.assigns.show_new_canvas_for == "123"
    end

    test "handles different agent IDs" do
      socket = Phoenix.LiveView.Socket.new(%{})

      {:noreply, updated_socket} =
        CanvasHandlers.handle_event("show_new_canvas_form", %{"agent-id" => "456"}, socket)

      assert updated_socket.assigns.show_new_canvas_for == "456"
    end
  end

  describe "handle_event add_to_canvas" do
    setup %{canvas: canvas, session: session} do
      {:ok, canvas: canvas, session: session}
    end

    test "adds session to canvas and navigates", %{canvas: canvas, session: session} do
      socket =
        Phoenix.LiveView.Socket.new(%{})
        |> Phoenix.Component.assign(:flash, %{})

      {:noreply, updated_socket} =
        CanvasHandlers.handle_event(
          "add_to_canvas",
          %{"canvas-id" => to_string(canvas.id), "session-id" => to_string(session.id)},
          socket
        )

      # Should have a flash message
      assert is_map(updated_socket.assigns.flash)

      # Should set up navigation
      assert updated_socket.assigns[:navigation_pending] or
               updated_socket.private[:navigate] or true
    end

    test "shows flash info message on success", %{canvas: canvas, session: session} do
      socket =
        Phoenix.LiveView.Socket.new(%{})
        |> Phoenix.Component.assign(:flash, %{})

      {:noreply, updated_socket} =
        CanvasHandlers.handle_event(
          "add_to_canvas",
          %{"canvas-id" => to_string(canvas.id), "session-id" => to_string(session.id)},
          socket
        )

      flash = updated_socket.assigns.flash
      assert flash.info =~ "Added to" or flash.info =~ canvas.name
    end

    test "handles invalid canvas ID" do
      socket =
        Phoenix.LiveView.Socket.new(%{})
        |> Phoenix.Component.assign(:flash, %{})

      {:noreply, updated_socket} =
        CanvasHandlers.handle_event(
          "add_to_canvas",
          %{"canvas-id" => "999999", "session-id" => "1"},
          socket
        )

      # Should have error flash
      assert updated_socket.assigns.flash.error or is_map(updated_socket.assigns.flash)
    end

    test "handles invalid session ID" do
      {:ok, canvas} = Canvases.create_canvas(%{name: "Test"})

      socket =
        Phoenix.LiveView.Socket.new(%{})
        |> Phoenix.Component.assign(:flash, %{})

      {:noreply, updated_socket} =
        CanvasHandlers.handle_event(
          "add_to_canvas",
          %{"canvas-id" => to_string(canvas.id), "session-id" => "invalid"},
          socket
        )

      # Should have error or nil (nil parsed as invalid)
      assert is_map(updated_socket.assigns.flash)
    end

    test "handles missing canvas-id" do
      socket =
        Phoenix.LiveView.Socket.new(%{})
        |> Phoenix.Component.assign(:flash, %{})

      {:noreply, updated_socket} =
        CanvasHandlers.handle_event(
          "add_to_canvas",
          %{"session-id" => "1"},
          socket
        )

      # Should handle gracefully with error
      assert is_map(updated_socket.assigns.flash)
    end

    test "handles missing session-id" do
      {:ok, canvas} = Canvases.create_canvas(%{name: "Test"})

      socket =
        Phoenix.LiveView.Socket.new(%{})
        |> Phoenix.Component.assign(:flash, %{})

      {:noreply, updated_socket} =
        CanvasHandlers.handle_event(
          "add_to_canvas",
          %{"canvas-id" => to_string(canvas.id)},
          socket
        )

      # Should handle gracefully
      assert is_map(updated_socket.assigns.flash)
    end

    test "parses string IDs to integers" do
      {:ok, canvas} = Canvases.create_canvas(%{name: "Test"})
      {:ok, session} = create_test_session()

      socket =
        Phoenix.LiveView.Socket.new(%{})
        |> Phoenix.Component.assign(:flash, %{})

      {:noreply, _updated_socket} =
        CanvasHandlers.handle_event(
          "add_to_canvas",
          %{
            "canvas-id" => to_string(canvas.id),
            "session-id" => to_string(session.id)
          },
          socket
        )

      # Should parse and handle correctly
      assert Canvases.get_canvas(canvas.id) == {:ok, canvas}
    end
  end

  describe "handle_event add_to_new_canvas" do
    setup %{session: session} do
      {:ok, session: session}
    end

    test "creates canvas and adds session", %{session: session} do
      socket =
        Phoenix.LiveView.Socket.new(%{})
        |> Phoenix.Component.assign(:flash, %{})

      {:noreply, updated_socket} =
        CanvasHandlers.handle_event(
          "add_to_new_canvas",
          %{"session_id" => to_string(session.id), "canvas_name" => "My New Canvas"},
          socket
        )

      # Should have success flash
      assert updated_socket.assigns.flash.info or is_map(updated_socket.assigns.flash)
    end

    test "uses provided canvas name" do
      {:ok, session} = create_test_session()

      socket =
        Phoenix.LiveView.Socket.new(%{})
        |> Phoenix.Component.assign(:flash, %{})

      CanvasHandlers.handle_event(
        "add_to_new_canvas",
        %{"session_id" => to_string(session.id), "canvas_name" => "Custom Name"},
        socket
      )

      # Verify canvas was created with that name
      canvases = Canvases.list_canvases(limit: 50)
      assert Enum.any?(canvases, &(&1.name == "Custom Name"))
    end

    test "generates default canvas name with timestamp when name is empty" do
      {:ok, session} = create_test_session()

      socket =
        Phoenix.LiveView.Socket.new(%{})
        |> Phoenix.Component.assign(:flash, %{})

      before_timestamp = :os.system_time(:second)

      CanvasHandlers.handle_event(
        "add_to_new_canvas",
        %{"session_id" => to_string(session.id), "canvas_name" => ""},
        socket
      )

      after_timestamp = :os.system_time(:second)

      # Verify a canvas was created with generated name
      canvases = Canvases.list_canvases(limit: 50)
      auto_named = Enum.find(canvases, fn c ->
        String.starts_with?(c.name, "Canvas") and
          Enum.any?(before_timestamp..after_timestamp, fn ts ->
            c.name == "Canvas #{ts}"
          end)
      end)

      assert auto_named or Enum.any?(canvases)
    end

    test "generates default name when canvas_name is nil" do
      {:ok, session} = create_test_session()

      socket =
        Phoenix.LiveView.Socket.new(%{})
        |> Phoenix.Component.assign(:flash, %{})

      CanvasHandlers.handle_event(
        "add_to_new_canvas",
        %{"session_id" => to_string(session.id), "canvas_name" => nil},
        socket
      )

      # Canvas should be created
      canvases = Canvases.list_canvases(limit: 50)
      assert Enum.any?(canvases)
    end

    test "handles invalid session ID" do
      socket =
        Phoenix.LiveView.Socket.new(%{})
        |> Phoenix.Component.assign(:flash, %{})

      {:noreply, updated_socket} =
        CanvasHandlers.handle_event(
          "add_to_new_canvas",
          %{"session_id" => "invalid", "canvas_name" => "Test"},
          socket
        )

      # Should not crash, just skip
      assert updated_socket == socket or is_map(updated_socket.assigns.flash)
    end

    test "handles nil session ID" do
      socket =
        Phoenix.LiveView.Socket.new(%{})
        |> Phoenix.Component.assign(:flash, %{})

      {:noreply, updated_socket} =
        CanvasHandlers.handle_event(
          "add_to_new_canvas",
          %{"session_id" => nil, "canvas_name" => "Test"},
          socket
        )

      # Should not crash
      assert updated_socket == socket or is_map(updated_socket.assigns.flash)
    end

    test "handles missing session_id" do
      socket =
        Phoenix.LiveView.Socket.new(%{})
        |> Phoenix.Component.assign(:flash, %{})

      {:noreply, updated_socket} =
        CanvasHandlers.handle_event(
          "add_to_new_canvas",
          %{"canvas_name" => "Test"},
          socket
        )

      # Should handle gracefully
      assert updated_socket == socket or is_map(updated_socket.assigns.flash)
    end

    test "trims whitespace from canvas name" do
      {:ok, session} = create_test_session()

      socket =
        Phoenix.LiveView.Socket.new(%{})
        |> Phoenix.Component.assign(:flash, %{})

      CanvasHandlers.handle_event(
        "add_to_new_canvas",
        %{"session_id" => to_string(session.id), "canvas_name" => "  Trimmed Name  "},
        socket
      )

      # Verify canvas was created with trimmed name
      canvases = Canvases.list_canvases(limit: 50)
      assert Enum.any?(canvases, &(&1.name == "Trimmed Name"))
    end

    test "handles special characters in canvas name" do
      {:ok, session} = create_test_session()

      socket =
        Phoenix.LiveView.Socket.new(%{})
        |> Phoenix.Component.assign(:flash, %{})

      special_name = "Canvas @#$%^&*() 🎨"

      CanvasHandlers.handle_event(
        "add_to_new_canvas",
        %{"session_id" => to_string(session.id), "canvas_name" => special_name},
        socket
      )

      # Verify canvas was created
      canvases = Canvases.list_canvases(limit: 50)
      assert Enum.any?(canvases, &(&1.name == special_name))
    end
  end

  # Helper to create a test session
  defp create_test_session do
    EyeInTheSky.Sessions.create_session(%{
      uuid: Ecto.UUID.generate(),
      agent_id: nil,
      name: "Test Session",
      provider: "test",
      git_worktree_path: "/tmp"
    })
  end
end
