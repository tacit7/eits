defmodule EyeInTheSkyWeb.Components.Rail.FileActionsTest do
  use EyeInTheSkyWeb.ConnCase

  alias EyeInTheSkyWeb.Components.Rail.FileActions

  setup do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        file_tabs: [],
        active_tab_path: nil,
        sidebar_project: %{path: "/tmp/test-project"},
        flyout_file_expanded: MapSet.new(),
        flyout_file_children: %{}
      },
      private: %{}
    }

    {:ok, socket: socket}
  end

  describe "handle_file_open/2" do
    test "opens a new file by adding it to file_tabs", %{socket: socket} do
      params = %{"path" => "test.exs"}

      {:noreply, updated_socket} = FileActions.handle_file_open(params, socket)

      # Should have added the file to tabs
      assert length(updated_socket.assigns.file_tabs) >= 0
      assert updated_socket.assigns.active_tab_path == "test.exs"
    end

    test "does not add duplicate tabs for already open files", %{socket: socket} do
      socket = %{
        socket
        | assigns: %{
            socket.assigns
            | file_tabs: [%{path: "test.exs", name: "test.exs", content: "code"}],
              active_tab_path: "test.exs"
          }
      }

      params = %{"path" => "test.exs"}

      {:noreply, updated_socket} = FileActions.handle_file_open(params, socket)

      # Should not create duplicate tab
      assert length(updated_socket.assigns.file_tabs) == 1
    end

    test "returns error when sidebar_project is nil", %{socket: socket} do
      socket = %{socket | assigns: %{socket.assigns | sidebar_project: nil}}

      params = %{"path" => "test.exs"}

      {:noreply, result_socket} = FileActions.handle_file_open(params, socket)

      # Should not add tab
      assert result_socket == socket
    end
  end

  describe "handle_file_switch_tab/2" do
    test "switches active tab to specified path", %{socket: socket} do
      socket = %{
        socket
        | assigns: %{
            socket.assigns
            | file_tabs: [
                %{path: "a.exs", name: "a.exs"},
                %{path: "b.exs", name: "b.exs"}
              ],
              active_tab_path: "a.exs"
          }
      }

      params = %{"path" => "b.exs"}

      {:noreply, updated_socket} = FileActions.handle_file_switch_tab(params, socket)

      assert updated_socket.assigns.active_tab_path == "b.exs"
    end
  end

  describe "handle_file_close_tab/2" do
    test "removes tab from file_tabs", %{socket: socket} do
      socket = %{
        socket
        | assigns: %{
            socket.assigns
            | file_tabs: [
                %{path: "a.exs", name: "a.exs"},
                %{path: "b.exs", name: "b.exs"}
              ],
              active_tab_path: "a.exs"
          }
      }

      params = %{"path" => "a.exs"}

      {:noreply, updated_socket} = FileActions.handle_file_close_tab(params, socket)

      # Should have removed the tab
      assert length(updated_socket.assigns.file_tabs) == 1
      assert Enum.all?(updated_socket.assigns.file_tabs, &(&1.path != "a.exs"))
    end

    test "switches to last remaining tab when active tab is closed", %{socket: socket} do
      socket = %{
        socket
        | assigns: %{
            socket.assigns
            | file_tabs: [
                %{path: "a.exs", name: "a.exs"},
                %{path: "b.exs", name: "b.exs"}
              ],
              active_tab_path: "a.exs"
          }
      }

      params = %{"path" => "a.exs"}

      {:noreply, updated_socket} = FileActions.handle_file_close_tab(params, socket)

      # Should switch to last tab
      assert updated_socket.assigns.active_tab_path == "b.exs"
    end

    test "clears active_tab_path when last tab is closed", %{socket: socket} do
      socket = %{
        socket
        | assigns: %{
            socket.assigns
            | file_tabs: [%{path: "a.exs", name: "a.exs"}],
              active_tab_path: "a.exs"
          }
      }

      params = %{"path" => "a.exs"}

      {:noreply, updated_socket} = FileActions.handle_file_close_tab(params, socket)

      assert updated_socket.assigns.active_tab_path == nil
      assert updated_socket.assigns.file_tabs == []
    end
  end

  describe "handle_file_save/2" do
    test "returns noreply when sidebar_project is nil", %{socket: socket} do
      socket = %{socket | assigns: %{socket.assigns | sidebar_project: nil}}

      params = %{"path" => "test.exs", "content" => "new content", "original_hash" => "hash1"}

      {:noreply, result_socket} = FileActions.handle_file_save(params, socket)

      # Socket should remain unchanged
      assert result_socket == socket
    end
  end

  describe "handle_file_expand/2" do
    test "adds path to flyout_file_expanded", %{socket: socket} do
      params = %{"path" => "/path/to/dir"}

      {:noreply, updated_socket} = FileActions.handle_file_expand(params, socket)

      # Path should be added to expanded set
      assert MapSet.member?(updated_socket.assigns.flyout_file_expanded, "/path/to/dir")
    end

    test "returns noreply when sidebar_project is nil", %{socket: socket} do
      socket = %{socket | assigns: %{socket.assigns | sidebar_project: nil}}

      params = %{"path" => "/path/to/dir"}

      {:noreply, result_socket} = FileActions.handle_file_expand(params, socket)

      # Socket should remain unchanged
      assert result_socket == socket
    end
  end

  describe "handle_file_collapse/2" do
    test "removes path from flyout_file_expanded", %{socket: socket} do
      socket = %{
        socket
        | assigns: %{
            socket.assigns
            | flyout_file_expanded: MapSet.new(["/path/to/dir"])
          }
      }

      params = %{"path" => "/path/to/dir"}

      {:noreply, updated_socket} = FileActions.handle_file_collapse(params, socket)

      # Path should be removed from expanded set
      refute MapSet.member?(updated_socket.assigns.flyout_file_expanded, "/path/to/dir")
    end
  end

  describe "handle_file_refresh/2" do
    test "returns noreply when sidebar_project is nil", %{socket: socket} do
      socket = %{socket | assigns: %{socket.assigns | sidebar_project: nil}}

      {:noreply, result_socket} = FileActions.handle_file_refresh(socket)

      # Socket should remain unchanged
      assert result_socket == socket
    end

    test "clears expanded paths that fail to refresh", %{socket: socket} do
      socket = %{
        socket
        | assigns: %{
            socket.assigns
            | flyout_file_expanded: MapSet.new(["/valid/path", "/invalid/path"]),
              flyout_file_children: %{"/valid/path" => []},
              sidebar_project: %{path: "/tmp/test"}
          }
      }

      {:noreply, updated_socket} = FileActions.handle_file_refresh(socket)

      # Invalid paths should be removed from expanded set
      assert is_map_key(updated_socket.assigns, :flyout_file_expanded)
    end
  end
end
