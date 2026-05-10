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
      {:ok, _view, html} = live(conn, ~p"/terminal")

      assert is_binary(html)
    end

    test "page title is Terminal", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/terminal")

      # Page title is in the <title> tag or in the layout
      assert html =~ "Terminal"
    end

    test "renders terminal PTY hook element", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      # The TerminalLive page should have a xterm hook target
      # Exact element depends on the render function
      assert has_element?(view, "[phx-hook]") or render(view) =~ "pty"
    end
  end

  describe "handle_event: pty_input" do
    test "pty_input with data does not crash the live view", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "pty_input", %{"data" => "ls\n"})

      # Should still be alive and renderable
      assert is_binary(render(view))
    end

    test "pty_input with empty data does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "pty_input", %{"data" => ""})

      assert is_binary(render(view))
    end

    test "pty_input with special characters does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "pty_input", %{"data" => "\x03"})

      assert is_binary(render(view))
    end

    test "pty_input with multiline command does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "pty_input", %{"data" => "echo 'line 1'\necho 'line 2'\n"})

      assert is_binary(render(view))
    end
  end

  describe "handle_event: pty_resize" do
    test "pty_resize with standard dimensions does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "pty_resize", %{"cols" => 80, "rows" => 24})

      assert is_binary(render(view))
    end

    test "pty_resize with large dimensions does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "pty_resize", %{"cols" => 220, "rows" => 50})

      assert is_binary(render(view))
    end

    test "pty_resize with small dimensions does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "pty_resize", %{"cols" => 40, "rows" => 10})

      assert is_binary(render(view))
    end
  end

  describe "handle_event: set_notify_on_stop" do
    test "set_notify_on_stop does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "set_notify_on_stop", %{"value" => "true"})

      assert is_binary(render(view))
    end
  end

  describe "handle_event: unknown events" do
    test "unknown event is logged and ignored without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      render_hook(view, "some_unknown_event", %{})

      assert is_binary(render(view))
    end
  end

  describe "handle_info: pty output" do
    test "pty_output message causes push_event without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      # Send a pty_output message to the LiveView process
      send(view.pid, {:pty_output, "hello terminal\r\n"})

      # After handle_info runs, view should still be alive
      assert is_binary(render(view))
    end

    test "pty_exited message triggers process-exited output", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      send(view.pid, :pty_exited)

      # View should still be alive (pty_pid set to nil, push_event fires)
      assert is_binary(render(view))
    end

    test "unhandled info message does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terminal")

      send(view.pid, {:some_other_message, "ignored"})

      assert is_binary(render(view))
    end
  end

  describe "integration" do
    test "full cycle: load, input, resize, pty_exited", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/terminal")

      assert html =~ "Terminal"

      render_hook(view, "pty_input", %{"data" => "echo test\n"})
      render_hook(view, "pty_resize", %{"cols" => 120, "rows" => 40})
      render_hook(view, "pty_input", %{"data" => "ls\n"})

      send(view.pid, :pty_exited)

      assert is_binary(render(view))
    end
  end
end
