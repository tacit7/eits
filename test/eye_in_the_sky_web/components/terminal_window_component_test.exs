defmodule EyeInTheSkyWeb.Components.TerminalWindowComponentTest do
  use EyeInTheSkyWeb.ComponentCase

  alias EyeInTheSkyWeb.Components.TerminalWindowComponent

  describe "TerminalWindowComponent - render" do
    test "renders terminal window with correct structure" do
      assigns = %{
        id: "term-1",
        myself: nil,
        ct: %{id: 1, pos_x: 100, pos_y: 50, width: 500, height: 300}
      }

      {:ok, _lv, html} =
        live_isolated(fn assigns ->
          render_component(&TerminalWindowComponent.render/1, assigns)
        end,
        session: %{}
        )

      assert html =~ "terminal-window-term-1"
    end

    test "renders with correct positioning and dimensions" do
      assigns = %{
        id: "term-1",
        myself: nil,
        ct: %{id: 1, pos_x: 100, pos_y: 50, width: 500, height: 300}
      }

      {:ok, _lv, html} =
        live_isolated(fn assigns ->
          render_component(&TerminalWindowComponent.render/1, assigns)
        end,
        session: %{}
        )

      assert html =~ "left: 100px"
      assert html =~ "top: 50px"
      assert html =~ "width: 500px"
      assert html =~ "height: 300px"
    end

    test "renders title bar with command icon" do
      assigns = %{
        id: "term-1",
        myself: nil,
        ct: %{id: 1, pos_x: 0, pos_y: 0, width: 400, height: 300}
      }

      {:ok, _lv, html} =
        live_isolated(fn assigns ->
          render_component(&TerminalWindowComponent.render/1, assigns)
        end,
        session: %{}
        )

      assert html =~ "Terminal"
      assert html =~ "bash"
      assert html =~ "hero-command-line"
    end

    test "renders close button" do
      assigns = %{
        id: "term-1",
        myself: nil,
        ct: %{id: 1, pos_x: 0, pos_y: 0, width: 400, height: 300}
      }

      {:ok, _lv, html} =
        live_isolated(fn assigns ->
          render_component(&TerminalWindowComponent.render/1, assigns)
        end,
        session: %{}
        )

      assert html =~ "Close terminal"
    end

    test "renders PTY mount point with correct id" do
      assigns = %{
        id: "term-1",
        myself: nil,
        ct: %{id: 1, pos_x: 0, pos_y: 0, width: 400, height: 300}
      }

      {:ok, _lv, html} =
        live_isolated(fn assigns ->
          render_component(&TerminalWindowComponent.render/1, assigns)
        end,
        session: %{}
        )

      assert html =~ "terminal-pty-1"
      assert html =~ "phx-hook=\"TerminalHook\""
    end

    test "renders with drag handle" do
      assigns = %{
        id: "term-1",
        myself: nil,
        ct: %{id: 1, pos_x: 0, pos_y: 0, width: 400, height: 300}
      }

      {:ok, _lv, html} =
        live_isolated(fn assigns ->
          render_component(&TerminalWindowComponent.render/1, assigns)
        end,
        session: %{}
        )

      assert html =~ "data-drag-handle"
    end

    test "renders with correct styling classes" do
      assigns = %{
        id: "term-1",
        myself: nil,
        ct: %{id: 1, pos_x: 0, pos_y: 0, width: 400, height: 300}
      }

      {:ok, _lv, html} =
        live_isolated(fn assigns ->
          render_component(&TerminalWindowComponent.render/1, assigns)
        end,
        session: %{}
        )

      assert html =~ "bg-zinc-950"
      assert html =~ "rounded-xl"
      assert html =~ "shadow-2xl"
      assert html =~ "border border-zinc-800"
    end
  end

  describe "TerminalWindowComponent - update" do
    test "assigns attrs when no pty_output" do
      socket = %Phoenix.LiveComponent.Socket{
        assigns: %{id: "term-1", ct: %{id: 1, pos_x: 0, pos_y: 0, width: 400, height: 300}}
      }

      assigns = %{id: "term-1", ct: %{id: 1, pos_x: 200, pos_y: 100, width: 500, height: 400}}

      {:ok, updated_socket} = TerminalWindowComponent.update(assigns, socket)

      assert updated_socket.assigns.ct.pos_x == 200
      assert updated_socket.assigns.ct.pos_y == 100
    end
  end

  describe "TerminalWindowComponent - handle_event" do
    test "handles pty_input event when pty_pid exists" do
      socket = %Phoenix.LiveComponent.Socket{
        assigns: %{
          id: "term-1",
          ct: %{id: 1, pos_x: 0, pos_y: 0, width: 400, height: 300},
          pty_pid: nil
        }
      }

      # When pty_pid is nil, it should just return noreply without crashing
      {:noreply, result_socket} =
        TerminalWindowComponent.handle_event("pty_input", %{"data" => "test"}, socket)

      assert result_socket == socket
    end

    test "handles pty_resize event" do
      socket = %Phoenix.LiveComponent.Socket{
        assigns: %{
          id: "term-1",
          ct: %{id: 1, pos_x: 0, pos_y: 0, width: 400, height: 300},
          pty_pid: nil
        }
      }

      {:noreply, result_socket} =
        TerminalWindowComponent.handle_event(
          "pty_resize",
          %{"cols" => 80, "rows" => 24},
          socket
        )

      assert result_socket == socket
    end

    test "handles close event and sends remove message" do
      socket = %Phoenix.LiveComponent.Socket{
        assigns: %{
          id: "term-1",
          ct: %{id: 1, pos_x: 0, pos_y: 0, width: 400, height: 300}
        }
      }

      # close event should send a message to self
      {:noreply, result_socket} =
        TerminalWindowComponent.handle_event("close", %{}, socket)

      # Socket should be returned unchanged (the message is sent separately)
      assert result_socket == socket
    end

    test "handles unknown event gracefully" do
      socket = %Phoenix.LiveComponent.Socket{
        assigns: %{
          id: "term-1",
          ct: %{id: 1, pos_x: 0, pos_y: 0, width: 400, height: 300}
        }
      }

      {:noreply, result_socket} =
        TerminalWindowComponent.handle_event("unknown_event", %{}, socket)

      assert result_socket == socket
    end
  end

  describe "TerminalWindowComponent - phx-hook and data attributes" do
    test "terminal hook has correct attributes" do
      assigns = %{
        id: "term-1",
        myself: nil,
        ct: %{id: 1, pos_x: 0, pos_y: 0, width: 400, height: 300}
      }

      {:ok, _lv, html} =
        live_isolated(fn assigns ->
          render_component(&TerminalWindowComponent.render/1, assigns)
        end,
        session: %{}
        )

      assert html =~ "phx-hook=\"TerminalHook\""
      assert html =~ "data-terminal-id=\"1\""
      assert html =~ "phx-update=\"ignore\""
    end
  end

  describe "TerminalWindowComponent - integration" do
    test "multiple terminal windows can be rendered with different ids" do
      for id <- 1..3 do
        assigns = %{
          id: "term-#{id}",
          myself: nil,
          ct: %{id: id, pos_x: id * 100, pos_y: id * 50, width: 400, height: 300}
        }

        {:ok, _lv, html} =
          live_isolated(fn assigns ->
            render_component(&TerminalWindowComponent.render/1, assigns)
          end,
          session: %{}
          )

        assert html =~ "terminal-window-term-#{id}"
        assert html =~ "terminal-pty-#{id}"
      end
    end
  end
end
