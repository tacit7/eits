defmodule EyeInTheSkyWeb.ProjectLive.Files do
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.Helpers.FileHelpers,
    only: [detect_file_type: 1, language_class: 1, get_file_size: 1, build_file_tree: 2, binary_file?: 1]

  import EyeInTheSkyWeb.Helpers.ProjectFileBrowserHelpers,
    only: [read_file_safe_detailed: 1, path_within?: 2]

  alias EyeInTheSky.Projects
  alias EyeInTheSky.Repo

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # Parse project ID safely
    project_id =
      case Integer.parse(id) do
        {int, ""} -> int
        _ -> nil
      end

    socket =
      if project_id do
        project =
          Projects.get_project!(project_id)
          |> Repo.preload([:agents])

        # Build file tree
        file_tree =
          if project.path do
            build_file_tree(project.path, project.path)
          else
            []
          end

        socket
        |> assign(:page_title, "Files - #{project.name}")
        |> assign(:project, project)
        |> assign(:sidebar_tab, :files)
        |> assign(:sidebar_project, project)
        |> assign(:file_path, nil)
        |> assign(:file_content, nil)
        |> assign(:file_type, nil)
        |> assign(:file_tree, file_tree)
        |> assign(:files, [])
        |> assign(:view_mode, :list)
        |> assign(:error, nil)
      else
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:file_path, nil)
        |> assign(:file_content, nil)
        |> assign(:file_type, nil)
        |> assign(:file_tree, [])
        |> assign(:files, [])
        |> assign(:view_mode, :list)
        |> assign(:error, "Invalid project ID")
        |> put_flash(:error, "Invalid project ID")
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"path" => path} = params, _uri, socket) do
    project = socket.assigns.project

    mode =
      case Map.get(params, "mode") do
        "tree" -> :tree
        _ -> :list
      end

    socket = assign(socket, :view_mode, mode)

    if project.path do
      full_path = Path.join(project.path, path)

      if not path_within?(full_path, project.path) do
        {:noreply,
         socket
         |> assign(:error, "Access denied: path outside project directory")
         |> assign(:file_content, nil)
         |> assign(:files, [])}
      else
        cond do
          File.dir?(full_path) ->
            # List directory contents (for list view)
            case File.ls(full_path) do
              {:ok, files} ->
                file_list =
                  files
                  |> Enum.filter(fn file ->
                    file_path = Path.join(full_path, file)
                    File.dir?(file_path) or !binary_file?(file_path)
                  end)
                  |> Enum.map(fn file ->
                    file_path = Path.join(full_path, file)

                    %{
                      name: file,
                      path: Path.join(path, file),
                      is_dir: File.dir?(file_path),
                      size: get_file_size(file_path)
                    }
                  end)
                  |> Enum.sort_by(&{!&1.is_dir, &1.name})

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

          File.regular?(full_path) ->
            case read_file_safe_detailed(full_path) do
              {:ok, content} ->
                {:noreply,
                 socket
                 |> assign(:file_path, path)
                 |> assign(:file_content, content)
                 |> assign(:file_type, detect_file_type(path))
                 |> assign(:files, [])
                 |> assign(:error, nil)}

              {:too_large} ->
                {:noreply,
                 socket
                 |> assign(:file_path, path)
                 |> assign(:file_content, nil)
                 |> assign(:file_type, nil)
                 |> assign(:files, [])
                 |> assign(:error, "File too large to display (over 1 MB)")}

              {:stat_error, reason} ->
                {:noreply,
                 socket
                 |> assign(:error, "Failed to stat file: #{reason}")
                 |> assign(:file_content, nil)}

              {:read_error, reason} ->
                {:noreply,
                 socket
                 |> assign(:error, "Failed to read file: #{reason}")
                 |> assign(:file_content, nil)}
            end

          true ->
            {:noreply,
             socket
             |> assign(:error, "File not found: #{path}")
             |> assign(:file_content, nil)
             |> assign(:files, [])}
        end
      end
    else
      {:noreply,
       socket
       |> assign(:error, "Project path not configured")
       |> assign(:file_content, nil)}
    end
  end

  def handle_params(params, _uri, socket) do
    # Load root directory for list view
    project = socket.assigns.project

    mode =
      case Map.get(params, "mode") do
        "tree" -> :tree
        _ -> :list
      end

    socket = assign(socket, :view_mode, mode)

    if project.path && mode == :list do
      case File.ls(project.path) do
        {:ok, files} ->
          ignored_dirs = ~w(node_modules _build deps dist .elixir_ls __pycache__ target vendor)

          file_list =
            files
            |> Enum.filter(fn file ->
              file_path = Path.join(project.path, file)

              (!String.starts_with?(file, ".") or file in [".claude", ".git"]) and
                file not in ignored_dirs and
                (File.dir?(file_path) or !binary_file?(file_path))
            end)
            |> Enum.map(fn file ->
              file_path = Path.join(project.path, file)

              %{
                name: file,
                path: file,
                is_dir: File.dir?(file_path),
                size: get_file_size(file_path)
              }
            end)
            |> Enum.sort_by(&{!&1.is_dir, &1.name})

          {:noreply, assign(socket, :files, file_list)}

        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
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
  def handle_info(_msg, socket), do: {:noreply, socket}

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
          <.link patch={~p"/projects/#{@project_id}/files?path=#{@item.path}"}>
            <.icon name="hero-document" class="w-4 h-4" />
            {@item.name}
            <%= if @item.size do %>
              <span class="badge badge-ghost badge-xs ml-auto">{@item.size}</span>
            <% end %>
          </.link>
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
        <div class="flex-1 min-h-0 overflow-y-auto">
          <%= if @error do %>
            <!-- Error Message -->
            <div class="p-4">
              <div class="alert alert-error">
                <.icon name="hero-x-circle" class="shrink-0 h-6 w-6" />
                <span>{@error}</span>
              </div>
            </div>
          <% end %>

          <%= if @file_content do %>
            <!-- File Content -->
            <div class="p-6">
              <div class="mb-4">
                <h2 class="text-lg font-semibold text-base-content">{Path.basename(@file_path)}</h2>
                <p class="text-sm text-base-content/60">{@file_path}</p>
              </div>
              <!-- Syntax Highlighted Code -->
              <div class="bg-base-200 rounded-lg overflow-x-auto">
                <pre class="text-sm"><code id="code-viewer" class={"language-#{language_class(@file_type)}"} phx-hook="Highlight"><%= @file_content %></code></pre>
              </div>
            </div>
          <% else %>
            <!-- Empty State -->
            <div class="flex items-center justify-center h-full">
              <div class="text-center">
                <.icon name="hero-document-text" class="w-16 h-16 mx-auto text-base-content/20 mb-4" />
                <h3 class="text-lg font-semibold text-base-content/60 mb-2">Select a file</h3>
                <p class="text-sm text-base-content/40">
                  Choose a file from the tree to view its contents
                </p>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    <% else %>
      <!-- List View -->
      <div class="h-[calc(100dvh-10rem)]">
        <div class="p-6">
          <%= if @error do %>
            <!-- Error Message -->
            <div class="alert alert-error mb-4">
              <.icon name="hero-x-circle" class="shrink-0 h-6 w-6" />
              <span>{@error}</span>
            </div>
          <% end %>

          <%= if @file_content do %>
            <!-- File Content -->
            <div class="mb-4">
              <div class="flex items-center gap-2 mb-4">
                <%= if @file_path && @file_path != "." do %>
                  <.link
                    patch={~p"/projects/#{@project.id}/files?path=#{Path.dirname(@file_path)}"}
                    class="btn btn-sm btn-ghost"
                  >
                    <.icon name="hero-arrow-left" class="w-4 h-4" /> Back
                  </.link>
                <% end %>
                <div>
                  <h2 class="text-lg font-semibold text-base-content">{Path.basename(@file_path)}</h2>
                  <p class="text-sm text-base-content/60">{@file_path}</p>
                </div>
              </div>
              <!-- Syntax Highlighted Code -->
              <div class="bg-base-200 rounded-lg overflow-x-auto">
                <pre class="text-sm"><code id="code-viewer" class={"language-#{language_class(@file_type)}"} phx-hook="Highlight"><%= @file_content %></code></pre>
              </div>
            </div>
          <% else %>
            <!-- Directory Listing -->
            <%= if length(@files) > 0 do %>
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
              <div class="md:hidden space-y-2">
                <%= for file <- @files do %>
                  <.link
                    patch={~p"/projects/#{@project.id}/files?path=#{file.path}"}
                    class="flex items-center gap-3 rounded-lg border border-base-content/10 bg-base-100 px-3 py-2"
                  >
                    <%= if file.is_dir do %>
                      <.icon name="hero-folder-solid" class="w-4 h-4 text-primary shrink-0" />
                    <% else %>
                      <.icon name="hero-document" class="w-4 h-4 shrink-0" />
                    <% end %>
                    <div class="min-w-0 flex-1">
                      <p class="truncate text-sm">{file.name}</p>
                      <p class="text-xs text-base-content/55">
                        {if file.is_dir, do: "Directory", else: file.size}
                      </p>
                    </div>
                  </.link>
                <% end %>
              </div>

              <div class="hidden md:block overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th>Name</th>
                      <th class="text-right">Size</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for file <- @files do %>
                      <tr class="hover">
                        <td>
                          <.link
                            patch={~p"/projects/#{@project.id}/files?path=#{file.path}"}
                            class="flex items-center gap-2"
                          >
                            <%= if file.is_dir do %>
                              <.icon name="hero-folder-solid" class="w-4 h-4 text-primary" />
                            <% else %>
                              <.icon name="hero-document" class="w-4 h-4" />
                            <% end %>
                            {file.name}
                          </.link>
                        </td>
                        <td class="text-right text-base-content/60">{file.size}</td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% else %>
              <!-- Empty State -->
              <div class="flex items-center justify-center h-[calc(100dvh-20rem)]">
                <div class="text-center">
                  <.icon
                    name="hero-document-text"
                    class="w-16 h-16 mx-auto text-base-content/20 mb-4"
                  />
                  <h3 class="text-lg font-semibold text-base-content/60 mb-2">No files</h3>
                  <p class="text-sm text-base-content/40">This directory is empty</p>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end
end
