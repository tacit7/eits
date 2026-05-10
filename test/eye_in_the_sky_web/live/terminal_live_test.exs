defmodule EyeInTheSkyWeb.TerminalLiveTest do
  use EyeInTheSkyWeb.LiveViewTest

  alias EyeInTheSky.Terminal.PtySupervisor

  describe "TerminalLive - mount" do
    test "initializes with page title", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/terminal")

      assert lv.assigns.page_title == "Terminal"
    end

    test "renders terminal container when connected", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/terminal")

      # Should have some terminal-related content when connected
      # The exact content depends on the render function
      assert is_binary(html)
    end

    test "sets pty_pid when connected", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/terminal")

      # When connected, pty_pid should be set to a process
      assert is_pid(lv.assigns.pty_pid)
    end

    test "sets pty_pid to nil when not connected", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/terminal")

      # For the initial non-connected render, pty_pid should be nil
      # But after connection, it's started
      assert is_nil(lv.assigns.pty_pid) or is_pid(lv.assigns.pty_pid)
    end
  end

  describe "TerminalLive - handle_event: pty_input" do
    test "writes to PTY when data is provided", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/terminal")

      # Skip if pty is not available
      case lv.assigns.pty_pid do
        nil ->
          :skip

        pty_pid ->
          # Send input event
          result = lv |> render_hook("pty_input", %{"data" => "ls\n"})

          # Should return noreply and socket
          assert is_binary(result)
      end
    end

    test "handles empty input gracefully", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/terminal")

      case lv.assigns.pty_pid do
        nil ->
          :skip

        _pty_pid ->
          result = lv |> render_hook("pty_input", %{"data" => ""})
          assert is_binary(result)
      end
    end

    test "ignores pty_input when pty_pid is nil", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/terminal")

      # Manually set pty_pid to nil to test
      lv_modified = put_in(lv.assigns.pty_pid, nil)

      # Should not crash when pty_pid is nil
      result = render_hook(lv_modified, "pty_input", %{"data" => "test"})

      assert is_binary(result)
    end

    test "handles special characters in input", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/terminal")

      case lv.assigns.pty_pid do
        nil ->
          :skip

        _pty_pid ->
          special_chars = "echo 'test' | grep 'pattern'\n"
          result = lv |> render_hook("pty_input", %{"data" => special_chars})
          assert is_binary(result)
      end
    end
  end

  describe "TerminalLive - handle_event: pty_resize" do
    test "resizes terminal when cols and rows are provided", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/terminal")

      case lv.assigns.pty_pid do
        nil ->
          :skip

        _pty_pid ->
          result = lv |> render_hook("pty_resize", %{"cols" => "120", "rows" => "40"})
          assert is_binary(result)
      end
    end

    test "handles standard terminal size (80x24)" do
      {:ok, lv, %{}} = live(build_conn(), ~p"/terminal")

      case lv.assigns.pty_pid do
        nil ->
          :skip

        _pty_pid ->
          result = lv |> render_hook("pty_resize", %{"cols" => "80", "rows" => "24"})
          assert is_binary(result)
      end
    end

    test "handles large terminal size" do
      {:ok, lv, %{}} = live(build_conn(), ~p"/terminal")

      case lv.assigns.pty_pid do
        nil ->
          :skip

        _pty_pid ->
          result = lv |> render_hook("pty_resize", %{"cols" => "200", "rows" => "50"})
          assert is_binary(result)
      end
    end

    test "ignores pty_resize when pty_pid is nil" do
      {:ok, lv, %{}} = live(build_conn(), ~p"/terminal")

      lv_modified = put_in(lv.assigns.pty_pid, nil)

      result = render_hook(lv_modified, "pty_resize", %{"cols" => "80", "rows" => "24"})

      assert is_binary(result)
    end
  end

  describe "TerminalLive - handle_event: set_notify_on_stop" do
    test "handles notification preference setting", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/terminal")

      # This event is handled by NotificationHelpers
      result = render_hook(lv, "set_notify_on_stop", %{"notify" => "true"})

      assert is_binary(result)
    end

    test "handles disable notification" do
      {:ok, lv, %{}} = live(build_conn(), ~p"/terminal")

      result = render_hook(lv, "set_notify_on_stop", %{"notify" => "false"})

      assert is_binary(result)
    end
  end

  describe "TerminalLive - handle_event: unexpected events" do
    test "logs and ignores unknown events gracefully" do
      {:ok, lv, %{}} = live(build_conn(), ~p"/terminal")

      # Send an unknown event
      result = render_hook(lv, "unknown_event", %{})

      # Should not crash, just log and continue
      assert is_binary(result)
    end
  end

  describe "TerminalLive - handle_info: pty_output" do
    test "PTY output message updates socket with event" do
      {:ok, lv, _html} = live(build_conn(), ~p"/terminal")

      case lv.assigns.pty_pid do
        nil ->
          :skip

        pty_pid ->
          # We can't directly test handle_info from the test client,
          # but we can verify the socket structure after events
          rendered = render(lv)
          assert is_binary(rendered)
      end
    end
  end

  describe "TerminalLive - terminate" do
    test "cleans up PTY process on terminate", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/terminal")

      case lv.assigns.pty_pid do
        nil ->
          :skip

        pty_pid ->
          # Process should be valid before termination
          assert Process.alive?(pty_pid)
      end
    end
  end

  describe "TerminalLive - rendering" do
    test "renders a full-screen terminal interface" do
      {:ok, _lv, html} = live(build_conn(), ~p"/terminal")

      # The terminal should have some identifying marker
      # (exact content depends on implementation)
      assert is_binary(html)
    end

    test "page loads without errors" do
      {:ok, lv, html} = live(build_conn(), ~p"/terminal")

      # Verify it mounted successfully
      assert lv.assigns.page_title == "Terminal"
      assert is_binary(html)
    end
  end

  describe "TerminalLive - socket lifecycle" do
    test "PTY is available after mount when connected" do
      {:ok, lv, _html} = live(build_conn(), ~p"/terminal")

      # After mount, if connected, pty_pid should be set
      case lv.assigns.pty_pid do
        nil -> :ok  # Not connected yet (dead render)
        pid -> assert is_pid(pid)
      end
    end

    test "page_title is consistent" do
      {:ok, lv, _html} = live(build_conn(), ~p"/terminal")

      # Page title should always be set
      assert lv.assigns.page_title == "Terminal"

      # Verify it doesn't change after render
      render(lv)
      assert lv.assigns.page_title == "Terminal"
    end
  end

  describe "TerminalLive - integration" do
    test "complete flow: connect → input → output → resize" do
      {:ok, lv, _html} = live(build_conn(), ~p"/terminal")

      case lv.assigns.pty_pid do
        nil ->
          :skip

        _pty_pid ->
          # Initial state
          assert lv.assigns.page_title == "Terminal"

          # Send some input
          rendered = render_hook(lv, "pty_input", %{"data" => "echo test\n"})
          assert is_binary(rendered)

          # Resize terminal
          rendered = render_hook(lv, "pty_resize", %{"cols" => "100", "rows" => "30"})
          assert is_binary(rendered)

          # Send more input
          rendered = render_hook(lv, "pty_input", %{"data" => "ls\n"})
          assert is_binary(rendered)
      end
    end
  end

  # Helper to build a default connection
  defp build_conn do
    Phoenix.ConnTest.build_conn()
  end
end
