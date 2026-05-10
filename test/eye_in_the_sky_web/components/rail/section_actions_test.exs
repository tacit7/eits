defmodule EyeInTheSkyWeb.Components.Rail.SectionActionsTest do
  use EyeInTheSkyWeb.ConnCase

  alias EyeInTheSkyWeb.Components.Rail.SectionActions

  setup do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        active_section: :sessions,
        flyout_open: false,
        mobile_open: false,
        proj_picker_open: false,
        show_new_session_form: false,
        sidebar_project: %{id: 1},
        sidebar_tab: :rail,
        session_sort: :recent,
        session_show: :active,
        session_name_filter: "",
        session_scope: :current,
        session_project_visible: %{},
        session_project_collapsed: MapSet.new(),
        flyout_sessions: []
      },
      private: %{}
    }

    {:ok, socket: socket}
  end

  describe "handle_toggle_section/2" do
    test "opens flyout when section is toggled", %{socket: socket} do
      socket = %{socket | assigns: %{socket.assigns | flyout_open: false}}

      params = %{"section" => "agents"}

      {:noreply, updated_socket} = SectionActions.handle_toggle_section(params, socket)

      assert updated_socket.assigns.flyout_open == true
      assert updated_socket.assigns.mobile_open == true
    end

    test "closes flyout when same section is toggled and flyout is open", %{socket: socket} do
      socket = %{
        socket
        | assigns: %{
            socket.assigns
            | active_section: :agents,
              flyout_open: true,
              mobile_open: true
          }
      }

      params = %{"section" => "agents"}

      {:noreply, updated_socket} = SectionActions.handle_toggle_section(params, socket)

      assert updated_socket.assigns.flyout_open == false
      assert updated_socket.assigns.mobile_open == false
    end

    test "changes section when different section is selected" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          active_section: :sessions,
          flyout_open: true,
          mobile_open: true,
          proj_picker_open: false,
          show_new_session_form: false,
          sidebar_project: %{id: 1},
          sidebar_tab: :rail,
          session_sort: :recent,
          session_show: :active,
          session_name_filter: "",
          session_scope: :current,
          session_project_visible: %{},
          session_project_collapsed: MapSet.new(),
          flyout_sessions: []
        },
        private: %{}
      }

      params = %{"section" => "agents"}

      {:noreply, updated_socket} = SectionActions.handle_toggle_section(params, socket)

      assert updated_socket.assigns.active_section == :agents
      assert updated_socket.assigns.flyout_open == true
    end

    test "resets proj_picker_open when toggling section", %{socket: socket} do
      socket = %{
        socket
        | assigns: %{socket.assigns | proj_picker_open: true}
      }

      params = %{"section" => "tasks"}

      {:noreply, updated_socket} = SectionActions.handle_toggle_section(params, socket)

      assert updated_socket.assigns.proj_picker_open == false
    end

    test "resets session project filters when toggling section", %{socket: socket} do
      socket = %{
        socket
        | assigns: %{
            socket.assigns
            | session_project_visible: %{1 => true},
              session_project_collapsed: MapSet.new([1])
          }
      }

      params = %{"section" => "notes"}

      {:noreply, updated_socket} = SectionActions.handle_toggle_section(params, socket)

      assert updated_socket.assigns.session_project_visible == %{}
      assert updated_socket.assigns.session_project_collapsed == MapSet.new()
    end
  end

  describe "handle_close_flyout/2" do
    test "closes flyout when no sticky section", %{socket: socket} do
      socket = %{
        socket
        | assigns: %{
            socket.assigns
            | sidebar_tab: :rail,
              flyout_open: true,
              mobile_open: true,
              proj_picker_open: true,
              show_new_session_form: true
          }
      }

      {:noreply, updated_socket} = SectionActions.handle_close_flyout(socket)

      assert updated_socket.assigns.flyout_open == false
      assert updated_socket.assigns.mobile_open == false
      assert updated_socket.assigns.proj_picker_open == false
      assert updated_socket.assigns.show_new_session_form == false
    end

    test "switches to sticky section when available", %{socket: socket} do
      socket = %{
        socket
        | assigns: %{
            socket.assigns
            | sidebar_tab: :chat,
              active_section: :agents,
              flyout_open: false
          }
      }

      {:noreply, updated_socket} = SectionActions.handle_close_flyout(socket)

      # Should switch to sticky section (depends on sidebar_tab)
      assert updated_socket.assigns.flyout_open == true
    end

    test "clears proj_picker_open when closing", %{socket: socket} do
      socket = %{
        socket
        | assigns: %{
            socket.assigns
            | proj_picker_open: true,
              flyout_open: true
          }
      }

      {:noreply, updated_socket} = SectionActions.handle_close_flyout(socket)

      assert updated_socket.assigns.proj_picker_open == false
    end

    test "clears show_new_session_form when closing", %{socket: socket} do
      socket = %{
        socket
        | assigns: %{
            socket.assigns
            | show_new_session_form: true,
              flyout_open: true
          }
      }

      {:noreply, updated_socket} = SectionActions.handle_close_flyout(socket)

      assert updated_socket.assigns.show_new_session_form == false
    end
  end
end
