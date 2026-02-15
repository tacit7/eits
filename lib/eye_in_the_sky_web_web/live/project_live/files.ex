defmodule EyeInTheSkyWebWeb.ProjectLive.Files do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Projects
  alias EyeInTheSkyWeb.Repo

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

        # Load tasks manually due to type mismatch
        tasks = Projects.get_project_tasks(project_id)

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
        |> assign(:tasks, tasks)
        |> assign(:file_path, nil)
        |> assign(:file_content, nil)
        |> assign(:rendered_content, nil)
        |> assign(:file_type, nil)
        |> assign(:file_tree, file_tree)
        |> assign(:files, [])
        |> assign(:view_mode, :list)
        |> assign(:error, nil)
      else
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:tasks, [])
        |> assign(:file_path, nil)
        |> assign(:file_content, nil)
        |> assign(:rendered_content, nil)
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
  def handle_params(%{"path" => path}, _uri, socket) do
    project = socket.assigns.project

    if project.path do
      full_path = Path.join(project.path, path)

      cond do
        File.dir?(full_path) ->
          # List directory contents (for list view)
          case File.ls(full_path) do
            {:ok, files} ->
              file_list =
                files
                |> Enum.filter(fn file ->
                  file_path = Path.join(full_path, file)
                  File.dir?(file_path) or !is_binary_file?(file_path)
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
          # Read file contents
          case File.read(full_path) do
            {:ok, content} ->
              file_type = detect_file_type(path)
              rendered_content = render_content(content, file_type)

              {:noreply,
               socket
               |> assign(:file_path, path)
               |> assign(:file_content, content)
               |> assign(:rendered_content, rendered_content)
               |> assign(:file_type, file_type)
               |> assign(:files, [])
               |> assign(:error, nil)}

            {:error, reason} ->
              {:noreply,
               socket
               |> assign(:error, "Failed to read file: #{reason}")
               |> assign(:file_content, nil)
               |> assign(:rendered_content, nil)}
          end

        true ->
          {:noreply,
           socket
           |> assign(:error, "File not found: #{path}")
           |> assign(:file_content, nil)
           |> assign(:files, [])}
      end
    else
      {:noreply,
       socket
       |> assign(:error, "Project path not configured")
       |> assign(:file_content, nil)}
    end
  end

  def handle_params(_params, _uri, socket) do
    # Load root directory for list view
    project = socket.assigns.project

    if project.path && socket.assigns.view_mode == :list do
      case File.ls(project.path) do
        {:ok, files} ->
          file_list =
            files
            |> Enum.filter(fn file ->
              file_path = Path.join(project.path, file)
              # Filter out binary files, but keep directories
              File.dir?(file_path) or !is_binary_file?(file_path)
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
    view_mode = String.to_existing_atom(mode)
    {:noreply, assign(socket, :view_mode, view_mode)}
  end

  defp build_file_tree(base_path, current_path, max_depth \\ 5, current_depth \\ 0) do
    if current_depth >= max_depth do
      []
    else
      case File.ls(current_path) do
        {:ok, files} ->
          files
          |> Enum.filter(fn file ->
            full_path = Path.join(current_path, file)
            # Filter out common ignored directories/files and binary files
            (!String.starts_with?(file, ".") or file in [".claude", ".git"]) and
              (File.dir?(full_path) or !is_binary_file?(full_path))
          end)
          |> Enum.map(fn file ->
            full_path = Path.join(current_path, file)
            relative_path = Path.relative_to(full_path, base_path)

            if File.dir?(full_path) do
              children = build_file_tree(base_path, full_path, max_depth, current_depth + 1)

              %{
                name: file,
                path: relative_path,
                type: :directory,
                children: Enum.sort_by(children, &{&1.type != :directory, &1.name})
              }
            else
              %{
                name: file,
                path: relative_path,
                type: :file,
                size: get_file_size(full_path)
              }
            end
          end)
          |> Enum.sort_by(&{&1.type != :directory, &1.name})

        {:error, _reason} ->
          []
      end
    end
  end

  defp get_file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> format_size(size)
      _ -> ""
    end
  end

  defp is_binary_file?(path) do
    # Common binary file extensions
    binary_extensions = [
      # Executables and libraries
      ".so",
      ".dll",
      ".dylib",
      ".exe",
      ".bin",
      ".o",
      ".a",
      ".lib",
      # Archives
      ".zip",
      ".tar",
      ".gz",
      ".bz2",
      ".xz",
      ".7z",
      ".rar",
      # Images
      ".jpg",
      ".jpeg",
      ".png",
      ".gif",
      ".bmp",
      ".ico",
      ".svg",
      ".webp",
      # Media
      ".mp3",
      ".mp4",
      ".avi",
      ".mov",
      ".mkv",
      ".wav",
      ".flac",
      # Documents
      ".pdf",
      ".doc",
      ".docx",
      ".xls",
      ".xlsx",
      ".ppt",
      ".pptx",
      # Databases
      ".db",
      ".sqlite",
      ".sqlite3",
      ".db-shm",
      ".db-wal",
      # Others
      ".wasm",
      ".beam",
      ".class",
      ".jar",
      ".war"
    ]

    extension = path |> Path.extname() |> String.downcase()
    Enum.member?(binary_extensions, extension)
  end

  defp format_size(size) when size < 1024, do: "#{size} B"
  defp format_size(size) when size < 1024 * 1024, do: "#{Float.round(size / 1024, 1)} KB"
  defp format_size(size), do: "#{Float.round(size / (1024 * 1024), 1)} MB"

  defp detect_file_type(path) do
    extension = path |> Path.extname() |> String.downcase()

    case extension do
      ".md" -> :markdown
      ".markdown" -> :markdown
      ".ex" -> :elixir
      ".exs" -> :elixir
      ".js" -> :javascript
      ".ts" -> :typescript
      ".jsx" -> :javascript
      ".tsx" -> :typescript
      ".json" -> :json
      ".yml" -> :yaml
      ".yaml" -> :yaml
      ".html" -> :html
      ".css" -> :css
      ".py" -> :python
      ".rb" -> :ruby
      ".go" -> :go
      ".rs" -> :rust
      ".java" -> :java
      ".c" -> :c
      ".cpp" -> :cpp
      ".sh" -> :bash
      ".sql" -> :sql
      ".xml" -> :xml
      _ -> :text
    end
  end

  defp render_content(_content, _), do: nil

  defp language_class(file_type) do
    case file_type do
      :markdown -> "markdown"
      :elixir -> "elixir"
      :javascript -> "javascript"
      :typescript -> "typescript"
      :json -> "json"
      :yaml -> "yaml"
      :html -> "html"
      :css -> "css"
      :python -> "python"
      :ruby -> "ruby"
      :go -> "go"
      :rust -> "rust"
      :java -> "java"
      :c -> "c"
      :cpp -> "cpp"
      :bash -> "bash"
      :sql -> "sql"
      :xml -> "xml"
      _ -> "plaintext"
    end
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
              <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 16 16">
                <path d="M1.75 1A1.75 1.75 0 0 0 0 2.75v10.5C0 14.216.784 15 1.75 15h12.5A1.75 1.75 0 0 0 16 13.25v-8.5A1.75 1.75 0 0 0 14.25 3H7.5a.25.25 0 0 1-.2-.1l-.9-1.2C6.07 1.26 5.55 1 5 1H1.75Z" />
              </svg>
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
            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 16 16">
              <path d="M4 0a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V2a2 2 0 0 0-2-2H4zm0 1h8a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V2a1 1 0 0 1 1-1z" />
            </svg>
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
            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 16 16">
              <path d="M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v1.5A1.75 1.75 0 0 1 14.25 5H1.75A1.75 1.75 0 0 1 0 3.25Zm0 7C0 7.784.784 7 1.75 7h12.5c.966 0 1.75.784 1.75 1.75v1.5A1.75 1.75 0 0 1 14.25 12H1.75A1.75 1.75 0 0 1 0 10.25Zm1.75-.25a.25.25 0 0 0-.25.25v1.5c0 .138.112.25.25.25h12.5a.25.25 0 0 0 .25-.25v-1.5a.25.25 0 0 0-.25-.25Z" />
            </svg>
            List
          </button>
          <button
            class={"btn btn-sm" <> if @view_mode == :tree, do: " btn-active", else: ""}
            phx-click="toggle_view_mode"
            phx-value-mode="tree"
          >
            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 16 16">
              <path d="M1.75 1A1.75 1.75 0 0 0 0 2.75v10.5C0 14.216.784 15 1.75 15h12.5A1.75 1.75 0 0 0 16 13.25v-8.5A1.75 1.75 0 0 0 14.25 3H7.5a.25.25 0 0 1-.2-.1l-.9-1.2C6.07 1.26 5.55 1 5 1H1.75Z" />
            </svg>
            Explore
          </button>
        </div>
      </div>
    </div>

    <%= if @view_mode == :tree do %>
      <!-- Tree View -->
      <div class="h-[calc(100vh-10rem)] flex">
        <!-- File Tree Sidebar -->
        <div
          id="file-tree-sidebar"
          class="w-80 border-r border-base-300 bg-base-100 overflow-y-auto"
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
        <div class="flex-1 overflow-y-auto">
          <%= if @error do %>
            <!-- Error Message -->
            <div class="p-4">
              <div class="alert alert-error">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="stroke-current shrink-0 h-6 w-6"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
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
              <%= if @rendered_content do %>
                <!-- Rendered Markdown -->
                <div class="prose prose-sm max-w-none dark:prose-invert bg-base-200 rounded-lg p-6 overflow-x-auto">
                  {@rendered_content}
                </div>
              <% else %>
                <!-- Syntax Highlighted Code -->
                <div class="bg-base-200 rounded-lg overflow-x-auto">
                  <pre class="text-sm"><code id="code-viewer" class={"language-#{language_class(@file_type)}"} phx-hook="Highlight"><%= @file_content %></code></pre>
                </div>
              <% end %>
            </div>
          <% else %>
            <!-- Empty State -->
            <div class="flex items-center justify-center h-full">
              <div class="text-center">
                <svg
                  class="w-16 h-16 mx-auto text-base-content/20 mb-4"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                  />
                </svg>
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
      <div class="h-[calc(100vh-10rem)]">
        <div class="p-6">
          <%= if @error do %>
            <!-- Error Message -->
            <div class="alert alert-error mb-4">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="stroke-current shrink-0 h-6 w-6"
                fill="none"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
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
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 16 16">
                      <path d="M8.22 2.97a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06-1.06l2.97-2.97H3.75a.75.75 0 0 1 0-1.5h7.44L8.22 4.03a.75.75 0 0 1 0-1.06Z" />
                    </svg>
                    Back
                  </.link>
                <% end %>
                <div>
                  <h2 class="text-lg font-semibold text-base-content">{Path.basename(@file_path)}</h2>
                  <p class="text-sm text-base-content/60">{@file_path}</p>
                </div>
              </div>
              <%= if @rendered_content do %>
                <!-- Rendered Markdown -->
                <div class="prose prose-sm max-w-none dark:prose-invert bg-base-200 rounded-lg p-6 overflow-x-auto">
                  {@rendered_content}
                </div>
              <% else %>
                <!-- Syntax Highlighted Code -->
                <div class="bg-base-200 rounded-lg overflow-x-auto">
                  <pre class="text-sm"><code id="code-viewer" class={"language-#{language_class(@file_type)}"} phx-hook="Highlight"><%= @file_content %></code></pre>
                </div>
              <% end %>
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
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 16 16">
                      <path d="M8.22 2.97a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06-1.06l2.97-2.97H3.75a.75.75 0 0 1 0-1.5h7.44L8.22 4.03a.75.75 0 0 1 0-1.06Z" />
                    </svg>
                    Back
                  </.link>
                <% end %>
                <h2 class="text-lg font-semibold text-base-content mb-2">
                  {@file_path || @project.name}
                </h2>
              </div>
              <div class="overflow-x-auto">
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
                              <svg
                                class="w-4 h-4 text-primary"
                                fill="currentColor"
                                viewBox="0 0 16 16"
                              >
                                <path d="M1.75 1A1.75 1.75 0 0 0 0 2.75v10.5C0 14.216.784 15 1.75 15h12.5A1.75 1.75 0 0 0 16 13.25v-8.5A1.75 1.75 0 0 0 14.25 3H7.5a.25.25 0 0 1-.2-.1l-.9-1.2C6.07 1.26 5.55 1 5 1H1.75Z" />
                              </svg>
                            <% else %>
                              <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 16 16">
                                <path d="M4 0a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V2a2 2 0 0 0-2-2H4zm0 1h8a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V2a1 1 0 0 1 1-1z" />
                              </svg>
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
              <div class="flex items-center justify-center h-[calc(100vh-20rem)]">
                <div class="text-center">
                  <svg
                    class="w-16 h-16 mx-auto text-base-content/20 mb-4"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                    />
                  </svg>
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
