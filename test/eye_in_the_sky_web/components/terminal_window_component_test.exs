defmodule EyeInTheSkyWeb.Components.TerminalWindowComponentTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.TerminalWindowComponent

  # Build a minimal assigns map suitable for rendering the component's render/1
  defp base_assigns(overrides \\ %{}) do
    Map.merge(
      %{
        id: "term-1",
        myself: %Phoenix.LiveComponent.CID{cid: 1},
        ct: %{id: 1, pos_x: 100, pos_y: 50, width: 500, height: 300}
      },
      overrides
    )
  end

  describe "TerminalWindowComponent - render" do
    test "renders terminal window with correct structure" do
      html = render_component(&TerminalWindowComponent.render/1, base_assigns())

      assert html =~ "terminal-window-term-1"
    end

    test "renders with correct positioning and dimensions" do
      html = render_component(&TerminalWindowComponent.render/1, base_assigns())

      assert html =~ "left: 100px"
      assert html =~ "top: 50px"
      assert html =~ "width: 500px"
      assert html =~ "height: 300px"
    end

    test "renders title bar with command icon" do
      html = render_component(&TerminalWindowComponent.render/1, base_assigns())

      assert html =~ "Terminal"
      assert html =~ "bash"
      assert html =~ "hero-command-line"
    end

    test "renders close button" do
      html = render_component(&TerminalWindowComponent.render/1, base_assigns())

      assert html =~ "Close terminal"
    end

    test "renders PTY mount point with correct id" do
      html = render_component(&TerminalWindowComponent.render/1, base_assigns())

      assert html =~ "terminal-pty-1"
      assert html =~ ~s(phx-hook="TerminalHook")
    end

    test "renders with drag handle" do
      html = render_component(&TerminalWindowComponent.render/1, base_assigns())

      assert html =~ "data-drag-handle"
    end

    test "renders with correct styling classes" do
      html = render_component(&TerminalWindowComponent.render/1, base_assigns())

      assert html =~ "bg-zinc-950"
      assert html =~ "rounded-xl"
      assert html =~ "shadow-2xl"
      assert html =~ "border border-zinc-800"
    end

    test "renders with TerminalWindowHook" do
      html = render_component(&TerminalWindowComponent.render/1, base_assigns())

      assert html =~ ~s(phx-hook="TerminalWindowHook")
    end

    test "renders with data-terminal-window attribute" do
      html = render_component(&TerminalWindowComponent.render/1, base_assigns())

      assert html =~ "data-terminal-window"
    end

    test "renders with phx-update=ignore on PTY container" do
      html = render_component(&TerminalWindowComponent.render/1, base_assigns())

      assert html =~ ~s(phx-update="ignore")
    end

    test "renders with data-terminal-id matching ct.id" do
      html = render_component(&TerminalWindowComponent.render/1, base_assigns())

      assert html =~ ~s(data-terminal-id="1")
    end

    test "different pos_x/pos_y/width/height are reflected in style" do
      assigns =
        base_assigns(%{
          ct: %{id: 2, pos_x: 300, pos_y: 200, width: 800, height: 600}
        })

      html = render_component(&TerminalWindowComponent.render/1, assigns)

      assert html =~ "left: 300px"
      assert html =~ "top: 200px"
      assert html =~ "width: 800px"
      assert html =~ "height: 600px"
    end

    test "different terminal ids produce different DOM ids" do
      html1 =
        render_component(
          &TerminalWindowComponent.render/1,
          base_assigns(%{id: "term-1", ct: %{id: 1, pos_x: 0, pos_y: 0, width: 400, height: 300}})
        )

      html2 =
        render_component(
          &TerminalWindowComponent.render/1,
          base_assigns(%{id: "term-2", ct: %{id: 2, pos_x: 0, pos_y: 0, width: 400, height: 300}})
        )

      assert html1 =~ "terminal-window-term-1"
      assert html2 =~ "terminal-window-term-2"
      assert html1 =~ "terminal-pty-1"
      assert html2 =~ "terminal-pty-2"
    end
  end

  describe "TerminalWindowComponent - update/2" do
    test "assigns all fields when no pty_output key" do
      # Build a socket using Phoenix.LiveView.Socket (not LiveComponent.Socket)
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          id: "term-1",
          ct: %{id: 1, pos_x: 0, pos_y: 0, width: 400, height: 300}
        },
        private: %{live_temp: %{}}
      }

      new_assigns = %{id: "term-1", ct: %{id: 1, pos_x: 200, pos_y: 100, width: 500, height: 400}}

      {:ok, updated} = TerminalWindowComponent.update(new_assigns, socket)

      assert updated.assigns.ct.pos_x == 200
      assert updated.assigns.ct.pos_y == 100
      assert updated.assigns.ct.width == 500
      assert updated.assigns.ct.height == 400
    end
  end

  describe "TerminalWindowComponent - handle_event/3" do
    defp bare_socket(extra_assigns \\ %{}) do
      assigns =
        Map.merge(
          %{
            __changed__: %{},
            id: "term-1",
            ct: %{id: 1, pos_x: 0, pos_y: 0, width: 400, height: 300}
          },
          extra_assigns
        )

      %Phoenix.LiveView.Socket{
        assigns: assigns,
        private: %{live_temp: %{}}
      }
    end

    test "pty_input with nil pty_pid is a no-op" do
      socket = bare_socket(%{pty_pid: nil})

      {:noreply, result} =
        TerminalWindowComponent.handle_event("pty_input", %{"data" => "ls\n"}, socket)

      assert result.assigns == socket.assigns
    end

    test "pty_resize with nil pty_pid is a no-op" do
      socket = bare_socket(%{pty_pid: nil})

      {:noreply, result} =
        TerminalWindowComponent.handle_event("pty_resize", %{"cols" => 80, "rows" => 24}, socket)

      assert result.assigns == socket.assigns
    end

    test "close sends :remove_terminal_window message to self" do
      socket = bare_socket()

      {:noreply, _result} = TerminalWindowComponent.handle_event("close", %{}, socket)

      assert_received {:remove_terminal_window, 1}
    end

    test "unknown event is a no-op" do
      socket = bare_socket()

      {:noreply, result} =
        TerminalWindowComponent.handle_event("totally_unknown", %{}, socket)

      assert result.assigns == socket.assigns
    end
  end
end
