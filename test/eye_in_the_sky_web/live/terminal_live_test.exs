defmodule EyeInTheSkyWeb.TerminalLiveTest do
  use EyeInTheSkyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    Application.put_env(:eye_in_the_sky, :disable_auth, true)
    on_exit(fn -> Application.delete_env(:eye_in_the_sky, :disable_auth) end)
    :ok
  end

  describe "mount and render" do
    test "page loads without error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      assert has_element?(view, "#terminal-container")
    end

    test "page title is Terminal", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/terminal")

      assert html =~ "Terminal"
    end

    test "renders terminal PTY hook element", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      assert has_element?(view, "#terminal-container[phx-hook='PtyHook']")
    end
  end

  describe "handle_event: pty_input" do
    test "pty_input with data does not crash the live view", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "pty_input", %{"data" => "ls\n"})

      assert has_element?(view, "#terminal-container")
    end

    test "pty_input with empty data does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "pty_input", %{"data" => ""})

      assert has_element?(view, "#terminal-container")
    end

    test "pty_input with special characters does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "pty_input", %{"data" => "\x03"})

      assert has_element?(view, "#terminal-container")
    end

    test "pty_input with multiline command does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "pty_input", %{"data" => "echo 'line 1'\necho 'line 2'\n"})

      assert has_element?(view, "#terminal-container")
    end
  end

  describe "handle_event: pty_resize" do
    test "pty_resize with standard dimensions does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "pty_resize", %{"cols" => 80, "rows" => 24})

      assert has_element?(view, "#terminal-container")
    end

    test "pty_resize with large dimensions does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "pty_resize", %{"cols" => 220, "rows" => 50})

      assert has_element?(view, "#terminal-container")
    end

    test "pty_resize with small dimensions does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "pty_resize", %{"cols" => 40, "rows" => 10})

      assert has_element?(view, "#terminal-container")
    end
  end

  describe "handle_event: set_notify_on_stop" do
    test "set_notify_on_stop does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "set_notify_on_stop", %{"value" => "true"})

      assert has_element?(view, "#terminal-container")
    end
  end

  describe "handle_event: unknown events" do
    test "unknown event is logged and ignored without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "some_unknown_event", %{})

      assert has_element?(view, "#terminal-container")
    end
  end

  describe "handle_info: pty output" do
    test "pty_output message causes push_event without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      send(view.pid, {:pty_output, "hello terminal\r\n"})

      # Terminal container still rendered; pty_pid remains set (PTY still alive)
      assert has_element?(view, "#terminal-container")
      %{socket: %{assigns: assigns}} = :sys.get_state(view.pid)
      assert is_pid(assigns.pty_pid)
    end

    test "pty_exited message sets pty_pid to nil", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      send(view.pid, :pty_exited)
      render(view)

      # pty_pid cleared; terminal container still renders (xterm.js handles display)
      %{socket: %{assigns: assigns}} = :sys.get_state(view.pid)
      assert is_nil(assigns.pty_pid)
      assert has_element?(view, "#terminal-container")
    end

    test "unhandled info message does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      send(view.pid, {:some_other_message, "ignored"})

      assert has_element?(view, "#terminal-container")
    end
  end

  describe "integration" do
    test "full cycle: load, input, resize, pty_exited", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/terminal")

      assert html =~ "Terminal"
      assert has_element?(view, "#terminal-container[phx-hook='PtyHook']")

      render_hook(view, "pty_input", %{"data" => "echo test\n"})
      render_hook(view, "pty_resize", %{"cols" => 120, "rows" => 40})
      render_hook(view, "pty_input", %{"data" => "ls\n"})

      send(view.pid, :pty_exited)
      render(view)

      %{socket: %{assigns: assigns}} = :sys.get_state(view.pid)
      assert is_nil(assigns.pty_pid)
      assert has_element?(view, "#terminal-container")
    end
  end
end
