defmodule EyeInTheSkyWeb.ProjectLive.Files do
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.Helpers.FileHelpers,
    only: [detect_file_type: 1, language_class: 1, binary_file?: 1, build_file_tree: 2, build_file_listing: 2, build_file_listing: 3]

  import EyeInTheSkyWeb.Helpers.ProjectFileBrowserHelpers,
    only: [read_file_safe_detailed: 1, path_within?: 2]

  import EyeInTheSkyWeb.Live.FileBrowserHelpers, only: [file_listing: 1]

  alias EyeInTheSky.Projects

  @ignored_dirs ~w(node_modules _build deps dist .elixir_ls __pycache__ target vendor)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      socket
      |> assign(:file_path, nil)
      |> assign(:file_content, nil)
      |> assign(:file_type, nil)
      |> assign(:file_tree, [])
      |> assign(:files, [])
      |> assign(:view_mode, :list)
      |> assign(:error, nil)

    case Integer.parse(id) do
      {project_id, ""} ->
        project = Projects.get_project!(project_id)

        socket =
          socket
          |> assign(:page_title, "Files - #{project.name}")
          |> assign(:project, project)
          |> assign(:sidebar_tab, :files)
          |> assign(:sidebar_project, project)

        socket =
          cond do
            connected?(socket) && project.path ->
              start_async(socket, :load_file_tree, fn ->
                build_file_tree(project.path, project.path)
              end)
            project.path ->
              assign(socket, :file_tree, build_file_tree(project.path, project.path))
            true ->
              socket
          end

        {:ok, socket}

      _ ->
        {:ok,
         socket
         |> assign(:page_title, "Project Not Found")
         |> assign(:project, nil)
         |> assign(:error, "Invalid project ID")
         |> put_flash(:error, "Invalid project ID")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mode = parse_mode(params)
    socket = assign(socket, :view_mode, mode)
    project = socket.assigns.project

    case {Map.get(params, "path"), project.path} do
      {path, proj_path} when is_binary(path) and is_binary(proj_path) ->
        full_path = Path.join(proj_path, path)
        handle_full_path(socket, full_path, path, proj_path)

      {path, nil} when is_binary(path) ->
        {:noreply,
         socket |> assign(:error, "Project path not configured") |> assign(:file_content, nil)}

      {nil, _} ->
        load_root_listing(socket, mode)
    end
  end

  defp parse_mode(params) do
    case Map.get(params, "mode") do
      "tree" -> :tree
      _ -> :list
    end
  end

  defp load_root_listing(socket, :list) do
    project = socket.assigns.project

    if not is_nil(project.path) do
      case build_file_listing(project.path, "", ignore_hidden: true, ignored_dirs: @ignored_dirs) do
        {:ok, file_list} -> {:noreply, assign(socket, :files, file_list)}
        {:error, _reason} -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  defp load_root_listing(socket, _mode), do: {:noreply, socket}

  defp handle_full_path(socket, full_path, path, project_path) do
    if not path_within?(full_path, project_path) do
      {:noreply,
       socket
       |> assign(:error, "Access denied: path outside project directory")
       |> assign(:file_content, nil)
       |> assign(:files, [])}
    else
      dispatch_path(socket, full_path, path)
    end
  end

  defp dispatch_path(socket, full_path, path) do
    case File.stat(full_path) do
      {:ok, %File.Stat{type: :directory}} ->
        handle_directory(socket, full_path, path)

      {:ok, %File.Stat{type: :regular}} ->
        handle_file(socket, full_path, path)

      _ ->
        {:noreply,
         socket
         |> assign(:error, "File not found: #{path}")
         |> assign(:file_content, nil)
         |> assign(:files, [])}
    end
  end

  defp handle_directory(socket, full_path, path) do
    case build_file_listing(full_path, path) do
      {:ok, file_list} ->
        {:noreply,
         socket
         |> assign(:file_path, path)
         |> assign(:file_content, nil)
         |> assign(:files, file_list)
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, "Failed to read directory: #{reason}")
         |> assign(:files, [])}
    end
  end

  defp handle_file(socket, full_path, path) do
    if binary_file?(path) do
      {:noreply,
       socket
       |> assign(:file_path, path)
       |> assign(:file_content, nil)
       |> assign(:file_type, nil)
       |> assign(:files, [])
       |> assign(:error, "Binary file — cannot preview")}
    else
    case read_file_safe_detailed(full_path) do
      {:ok, content} ->
        {:noreply,
         socket
         |> assign(:file_path, path)
         |> assign(:file_content, content)
         |> assign(:file_type, detect_file_type(path))
         |> assign(:files, [])
         |> assign(:error, nil)}

      {:error, :too_large} ->
        {:noreply,
         socket
         |> assign(:file_path, path)
         |> assign(:file_content, nil)
         |> assign(:file_type, nil)
         |> assign(:files, [])
         |> assign(:error, "File too large to display (over 1 MB)")}

      {:error, {:stat_error, reason}} ->
        {:noreply,
         socket
         |> assign(:error, "Failed to stat file: #{reason}")
         |> assign(:file_content, nil)}

      {:error, {:read_error, reason}} ->
        {:noreply,
         socket
         |> assign(:error, "Failed to read file: #{reason}")
         |> assign(:file_content, nil)}
    end
    end
  end

  @impl true
  def handle_event("toggle_view_mode", %{"mode" => mode}, socket) do
    project = socket.assigns.project

    case mode do
      "list" ->
        {:noreply, push_patch(socket, to: ~p"/projects/#{project.id}/files?mode=list")}

      "tree" ->
        {:noreply, push_patch(socket, to: ~p"/projects/#{project.id}/files?mode=tree")}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_notify_on_stop", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:load_file_tree, {:ok, tree}, socket) do
    {:noreply, assign(socket, :file_tree, tree)}
  end

  def handle_async(:load_file_tree, {:exit, _reason}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  attr :error, :string, default: nil
  attr :file_content, :string, default: nil
  attr :file_type, :string, default: nil
  attr :file_path, :string, default: nil
  attr :project, :map, required: true
  attr :show_back_button, :boolean, default: false
  attr :empty_label, :string, default: "Select a file"
  attr :empty_description, :string, default: "Choose a file from the tree to view its contents"

  defp file_content_pane(assigns) do
    ~H"""
    <%= if @error do %>
      <div class="p-4">
        <div class="alert alert-error">
          <.icon name="hero-x-circle" class="shrink-0 h-6 w-6" />
          <span>{@error}</span>
        </div>
      </div>
    <% end %>
    <%= if @file_content do %>
      <div class="flex flex-col h-full">
        <div class="px-4 py-3 border-b border-base-300 shrink-0 flex items-center gap-2">
          <%= if @show_back_button && @file_path && @file_path != "." do %>
            <.link
              patch={~p"/projects/#{@project.id}/files?path=#{Path.dirname(@file_path)}"}
              class="btn btn-sm btn-ghost btn-square"
            >
              <.icon name="hero-arrow-left" class="w-4 h-4" />
            </.link>
          <% end %>
          <div>
            <h2 class="text-sm font-semibold text-base-content">{Path.basename(@file_path)}</h2>
            <p class="text-xs text-base-content/50">{@file_path}</p>
          </div>
        </div>
        <div class="flex-1 min-h-0 overflow-hidden">
          <.file_content_viewer file_content={@file_content} file_type={@file_type} />
        </div>
      </div>
    <% else %>
      <div class="flex items-center justify-center h-full">
        <div class="text-center">
          <.icon name="hero-document-text" class="w-16 h-16 mx-auto text-base-content/20 mb-4" />
          <h3 class="text-lg font-semibold text-base-content/60 mb-2">{@empty_label}</h3>
          <p class="text-sm text-base-content/40">{@empty_description}</p>
        </div>
      </div>
    <% end %>
    """
  end

  attr :file_content, :string, required: true
  attr :file_type, :string, default: nil

  defp file_content_viewer(assigns) do
    assigns = assign(assigns, :viewer_id, "codemirror-#{:erlang.phash2(assigns.file_content)}")
    ~H"""
    <div
      id={@viewer_id}
      phx-hook="CodeMirror"
      phx-update="ignore"
      data-content={Base.encode64(@file_content)}
      data-lang={language_class(@file_type)}
      data-readonly="true"
      class="h-full"
    >
    </div>
    """
  end

  attr :item, :map, required: true
  attr :project_id, :integer, required: true

  defp tree_item(assigns) do
    case assigns.item.type do
      :directory ->
        ~H"""
        <li>
          <details>
            <summary>
              <.icon name="hero-folder" class="w-4 h-4" />
              {@item.name}
            </summary>
            <ul>
              <.tree_item :for={child <- @item.children} item={child} project_id={@project_id} />
            </ul>
          </details>
        </li>
        """

      :file ->
        ~H"""
        <li>
          <%= if binary_file?(@item.name) do %>
            <span class="opacity-40 cursor-not-allowed pointer-events-none" title="Binary file — cannot preview">
              <.icon name="hero-no-symbol" class="w-4 h-4" />
              {@item.name}
              <span class="badge badge-ghost badge-xs ml-auto font-mono">bin</span>
            </span>
          <% else %>
            <.link patch={~p"/projects/#{@project_id}/files?path=#{@item.path}"}>
              <.icon name="hero-document" class="w-4 h-4" />
              {@item.name}
              <%= if @item.size do %>
                <span class="badge badge-ghost badge-xs ml-auto">{@item.size}</span>
              <% end %>
            </.link>
          <% end %>
        </li>
        """
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!-- View Mode Toggle -->
    <div class="bg-base-100 border-b border-base-300">
      <div class="px-4 sm:px-6 lg:px-8 py-2">
        <div class="btn-group btn-group-sm">
          <button
            class={"btn btn-sm" <> if @view_mode == :list, do: " btn-active", else: ""}
            phx-click="toggle_view_mode"
            phx-value-mode="list"
          >
            <.icon name="hero-bars-3" class="w-4 h-4" /> List
          </button>
          <button
            class={"btn btn-sm" <> if @view_mode == :tree, do: " btn-active", else: ""}
            phx-click="toggle_view_mode"
            phx-value-mode="tree"
          >
            <.icon name="hero-folder" class="w-4 h-4" /> Explore
          </button>
        </div>
      </div>
    </div>

    <%= if @view_mode == :tree do %>
      <.file_tree_view {assigns} />
    <% else %>
      <.file_list_view {assigns} />
    <% end %>
    """
  end

  defp file_tree_view(assigns) do
    ~H"""
    <!-- Tree View -->
    <div class="h-[calc(100dvh-10rem)] flex flex-col md:flex-row">
      <!-- File Tree Sidebar -->
      <div
        id="file-tree-sidebar"
        class="w-full md:w-80 md:flex-shrink-0 border-b md:border-b-0 md:border-r border-base-300 bg-base-100 overflow-y-auto max-h-64 md:max-h-none"
        phx-update="ignore"
      >
        <div class="p-4">
          <h2 class="text-sm font-semibold text-base-content/80 mb-2">Files</h2>
          <ul class="menu menu-sm bg-base-200 rounded-lg">
            <.tree_item :for={item <- @file_tree} item={item} project_id={@project.id} />
          </ul>
        </div>
      </div>
      
    <!-- File Content Viewer -->
      <div class="flex-1 min-h-0 overflow-hidden">
        <.file_content_pane
          error={@error}
          file_content={@file_content}
          file_type={@file_type}
          file_path={@file_path}
          project={@project}
          show_back_button={false}
          empty_label="Select a file"
          empty_description="Choose a file from the tree to view its contents"
        />
      </div>
    </div>
    """
  end

  defp file_list_view(assigns) do
    ~H"""
    <!-- List View -->
    <div class="h-[calc(100dvh-10rem)]">
      <%= if @files != [] && !@file_content do %>
        <!-- Directory Listing -->
        <div class="p-6">
          <%= if @error do %>
            <div class="alert alert-error mb-4">
              <.icon name="hero-x-circle" class="shrink-0 h-6 w-6" />
              <span>{@error}</span>
            </div>
          <% end %>
          <div class="mb-4">
            <%= if @file_path && @file_path != "." do %>
              <.link
                patch={~p"/projects/#{@project.id}/files?path=#{Path.dirname(@file_path)}"}
                class="btn btn-sm btn-ghost mb-4"
              >
                <.icon name="hero-arrow-left" class="w-4 h-4" /> Back
              </.link>
            <% end %>
            <h2 class="text-lg font-semibold text-base-content mb-2">
              {@file_path || @project.name}
            </h2>
          </div>
          <.file_listing
            files={@files}
            patch_fn={fn path -> ~p"/projects/#{@project.id}/files?path=#{path}" end}
          />
        </div>
      <% else %>
        <.file_content_pane
          error={@error}
          file_content={@file_content}
          file_type={@file_type}
          file_path={@file_path}
          project={@project}
          show_back_button={true}
          empty_label="No files"
          empty_description="This directory is empty"
        />
      <% end %>
    </div>
    """
  end
end
