defmodule EyeInTheSkyWeb.ProjectLive.Config do
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]
  import EyeInTheSkyWeb.Helpers.FileHelpers, only: [detect_file_type: 1]
  import EyeInTheSkyWeb.Helpers.ProjectFileBrowserHelpers
  import EyeInTheSkyWeb.Components.ConfigBrowser
  import EyeInTheSkyWeb.Live.FileBrowserHelpers, only: [read_file_for_display: 4]

  alias EyeInTheSky.Projects
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project_id = parse_int(id)

    socket =
      socket
      |> assign(default_assigns())
      |> assign(:page_title, "Config")
      |> assign(:project, nil)
      |> assign(:sidebar_tab, :config)
      |> assign(:sidebar_project, nil)
      |> assign(:claude_dir, nil)

    socket =
      cond do
        is_nil(project_id) ->
          socket
          |> assign(:page_title, "Project Not Found")
          |> put_flash(:error, "Invalid project ID")

        connected?(socket) ->
          project = Projects.get_project!(project_id)
          claude_dir = if project.path, do: Path.join(project.path, ".claude"), else: nil

          socket
          |> assign(:page_title, "Config - #{project.name}")
          |> assign(:project, project)
          |> assign(:sidebar_project, project)
          |> assign(:claude_dir, claude_dir)

        true ->
          socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mode =
      case Map.get(params, "mode") do
        "list" -> :list
        _ -> :tree
      end

    socket = assign(socket, :view_mode, mode)

    case mode do
      :list ->
        path = Map.get(params, "path")
        {:noreply, load_list_path(socket, path)}

      :tree ->
        claude_dir = socket.assigns.claude_dir

        entries =
          if not is_nil(claude_dir) && File.dir?(claude_dir),
            do: scan_directory(claude_dir, claude_dir, 0),
            else: []

        {:noreply, assign(socket, :entries, entries)}
    end
  end

  @impl true
  def handle_event("view_file", %{"path" => path}, socket) do
    claude_dir = socket.assigns.claude_dir

    if not is_nil(claude_dir) && String.starts_with?(path, claude_dir) do
      content =
        case File.read(path) do
          {:ok, data} -> data
          {:error, _} -> "Error: could not read file"
        end

      relative = Path.relative_to(path, claude_dir)
      file_type = detect_file_type(path)

      {:noreply,
       socket
       |> assign(:selected_file, relative)
       |> assign(:selected_file_path, path)
       |> assign(:file_content, content)
       |> assign(:file_type, file_type)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_viewer", _params, socket) do
    {:noreply, clear_file_assigns(socket)}
  end

  @impl true
  def handle_event("open_file", _params, socket) do
    path = socket.assigns.selected_file_path
    claude_dir = socket.assigns.claude_dir

    if not is_nil(path) && not is_nil(claude_dir) && String.starts_with?(path, claude_dir) &&
         File.exists?(path) do
      EyeInTheSkyWeb.Helpers.ViewHelpers.open_in_system(path)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_view_mode", %{"mode" => mode}, socket) do
    project = socket.assigns.project

    case mode do
      "list" ->
        {:noreply, push_patch(socket, to: ~p"/projects/#{project.id}/config?mode=list")}

      "tree" ->
        {:noreply, push_patch(socket, to: ~p"/projects/#{project.id}/config?mode=tree")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  # ── Private helpers ──────────────────────────────────────────────────────────

  defp default_assigns do
    [
      selected_file: nil,
      selected_file_path: nil,
      file_content: nil,
      file_type: nil,
      entries: [],
      files: [],
      current_path: nil,
      view_mode: :tree,
      error: nil
    ]
  end

  defp load_list_path(socket, path) do
    claude_dir = socket.assigns.claude_dir

    if claude_dir && File.dir?(claude_dir) do
      case resolve_list_target(path, claude_dir) do
        {:error, msg} ->
          assign(socket, :error, msg)

        {:ok, full_path, rel_path} ->
          case dispatch_path(full_path, rel_path, path, claude_dir) do
            {:dir, files, dir_rel_path} ->
              socket
              |> assign(:files, files)
              |> assign(:current_path, dir_rel_path)
              |> assign(:file_content, nil)
              |> assign(:selected_file, nil)
              |> assign(:selected_file_path, nil)
              |> assign(:file_type, nil)
              |> assign(:error, nil)

            {:file, full_path, file_rel_path} ->
              # Always clear the listing and set current_path regardless of success/error,
              # matching the original pre-refactor behavior of this module.
              socket
              |> read_file_for_display(full_path, file_rel_path, claude_dir)
              |> assign(:current_path, file_rel_path)
              |> assign(:files, [])

            {:error, msg} ->
              assign(socket, :error, msg)
          end
      end
    else
      assign(socket, :error, "No .claude directory found")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @claude_dir && File.dir?(@claude_dir) do %>
      <!-- View Mode Toggle -->
      <div class="bg-base-100 border-b border-base-300">
        <div class="px-4 sm:px-6 lg:px-8 py-2">
          <div class="join">
            <button
              class={"btn btn-sm join-item" <> if @view_mode == :tree, do: " btn-active", else: ""}
              phx-click="toggle_view_mode"
              phx-value-mode="tree"
            >
              <.icon name="hero-folder" class="size-4" /> Explore
            </button>
            <button
              class={"btn btn-sm join-item" <> if @view_mode == :list, do: " btn-active", else: ""}
              phx-click="toggle_view_mode"
              phx-value-mode="list"
            >
              <.icon name="hero-bars-3" class="size-4" /> List
            </button>
          </div>
        </div>
      </div>

      <%= if @view_mode == :tree do %>
        <.tree_view {assigns} />
      <% else %>
        <.list_view {assigns} />
      <% end %>
    <% else %>
      <div class="flex items-center justify-center h-[calc(100dvh-10rem)]">
        <.empty_state
          icon="hero-cog-6-tooth"
          title="No .claude directory"
          subtitle={
            if not is_nil(@project) && not is_nil(@project.path),
              do: "No .claude directory found at #{@project.path}",
              else: "Project path not configured"
          }
        />
      </div>
    <% end %>
    """
  end
end
