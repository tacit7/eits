defmodule EyeInTheSkyWeb.ProjectLive.Config do
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.Helpers.FileHelpers, only: [path_within?: 2]

  alias EyeInTheSky.Projects

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project_id =
      case Integer.parse(id) do
        {int, ""} -> int
        _ -> nil
      end

    socket =
      socket
      |> assign(:selected_file, nil)
      |> assign(:selected_file_path, nil)
      |> assign(:file_content, nil)
      |> assign(:file_type, nil)
      |> assign(:entries, [])
      |> assign(:files, [])
      |> assign(:current_path, nil)
      |> assign(:view_mode, :tree)
      |> assign(:error, nil)

    socket =
      if project_id do
        project =
          Projects.get_project_with_agents!(project_id)

        claude_dir = if project.path, do: Path.join(project.path, ".claude"), else: nil

        socket
        |> assign(:page_title, "Config - #{project.name}")
        |> assign(:project, project)
        |> assign(:sidebar_tab, :config)
        |> assign(:sidebar_project, project)
        |> assign(:claude_dir, claude_dir)
      else
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:claude_dir, nil)
        |> put_flash(:error, "Invalid project ID")
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
          if claude_dir && File.dir?(claude_dir),
            do: scan_directory(claude_dir, claude_dir, 0),
            else: []

        {:noreply, assign(socket, :entries, entries)}
    end
  end

  @impl true
  def handle_event("view_file", %{"path" => path}, socket) do
    claude_dir = socket.assigns.claude_dir

    if claude_dir && path_within?(path, claude_dir) do
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
    {:noreply,
     socket
     |> assign(:selected_file, nil)
     |> assign(:selected_file_path, nil)
     |> assign(:file_content, nil)
     |> assign(:file_type, nil)}
  end

  @impl true
  def handle_event("open_file", _params, socket) do
    path = socket.assigns.selected_file_path
    claude_dir = socket.assigns.claude_dir

    if path && claude_dir && path_within?(path, claude_dir) && File.exists?(path) do
      EyeInTheSkyWeb.Helpers.ViewHelpers.open_in_system(path)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("file_changed", %{"content" => content}, socket) do
    path = socket.assigns.selected_file_path
    claude_dir = socket.assigns.claude_dir

    if path && claude_dir && path_within?(path, claude_dir) do
      case File.write(path, content) do
        :ok -> {:noreply, put_flash(socket, :info, "Saved")}
        {:error, reason} -> {:noreply, put_flash(socket, :error, "Save failed: #{reason}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Access denied")}
    end
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

  # ── Private helpers ──────────────────────────────────────────────────────────

  defp load_list_path(socket, path) do
    claude_dir = socket.assigns.claude_dir

    unless claude_dir && File.dir?(claude_dir) do
      assign(socket, :error, "No .claude directory found")
    else
      case resolve_list_target(claude_dir, path) do
        {:error, msg} ->
          assign(socket, :error, msg)

        {:ok, full_path, rel_path} ->
          cond do
            File.dir?(full_path) -> list_directory(socket, full_path, rel_path)
            File.regular?(full_path) -> read_file_for_display(socket, full_path, rel_path)
            true -> assign(socket, :error, "Path not found: #{path}")
          end
      end
    end
  end

  defp resolve_list_target(claude_dir, path) do
    if path && path != "" do
      full = Path.join(claude_dir, path)

      if path_within?(full, claude_dir),
        do: {:ok, full, path},
        else: {:error, "Access denied"}
    else
      {:ok, claude_dir, nil}
    end
  end

  defp list_directory(socket, full_path, rel_path) do
    case File.ls(full_path) do
      {:ok, items} ->
        file_list =
          items
          |> Enum.sort()
          |> Enum.map(fn item ->
            item_path = Path.join(full_path, item)
            rel = if rel_path, do: Path.join(rel_path, item), else: item

            size =
              case File.stat(item_path) do
                {:ok, %{size: s}} -> s
                _ -> 0
              end

            %{name: item, path: rel, is_dir: File.dir?(item_path), size: size}
          end)
          |> Enum.sort_by(&{!&1.is_dir, &1.name})

        socket
        |> assign(:files, file_list)
        |> assign(:current_path, rel_path)
        |> assign(:file_content, nil)
        |> assign(:selected_file, nil)
        |> assign(:selected_file_path, nil)
        |> assign(:file_type, nil)
        |> assign(:error, nil)

      {:error, reason} ->
        assign(socket, :error, "Failed to read directory: #{reason}")
    end
  end

  defp read_file_for_display(socket, full_path, rel_path) do
    case File.stat(full_path) do
      {:ok, %{size: size}} when size > 1_048_576 ->
        socket
        |> assign(:current_path, rel_path)
        |> assign(:file_content, nil)
        |> assign(:files, [])
        |> assign(:error, "File too large to display (over 1 MB)")

      {:ok, _} ->
        case File.read(full_path) do
          {:ok, content} ->
            file_type = detect_file_type(full_path)

            socket
            |> assign(:current_path, rel_path)
            |> assign(:file_content, content)
            |> assign(:selected_file, rel_path)
            |> assign(:selected_file_path, full_path)
            |> assign(:file_type, file_type)
            |> assign(:files, [])
            |> assign(:error, nil)

          {:error, reason} ->
            assign(socket, :error, "Failed to read file: #{reason}")
        end

      {:error, reason} ->
        assign(socket, :error, "Failed to stat file: #{reason}")
    end
  end

  @max_tree_depth 2

  defp scan_directory(base_dir, current_dir, depth) do
    case File.ls(current_dir) do
      {:ok, items} ->
        items
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.sort()
        |> Enum.map(fn item ->
          full = Path.join(current_dir, item)
          relative = Path.relative_to(full, base_dir)
          is_dir = File.dir?(full)

          if is_dir do
            children =
              if depth < @max_tree_depth,
                do: scan_directory(base_dir, full, depth + 1),
                else: []

            %{name: item, path: full, relative: relative, is_dir: true, children: children}
          else
            size =
              case File.stat(full) do
                {:ok, %{size: s}} -> s
                _ -> 0
              end

            %{name: item, path: full, relative: relative, is_dir: false, size: size}
          end
        end)
        |> Enum.sort_by(&{!&1.is_dir, &1.name})

      _ ->
        []
    end
  end

  defp detect_file_type(path) do
    ext = path |> Path.extname() |> String.downcase()

    case ext do
      ".md" -> :markdown
      ".json" -> :json
      ".ex" -> :elixir
      ".exs" -> :elixir
      ".sh" -> :bash
      ".yml" -> :yaml
      ".yaml" -> :yaml
      ".toml" -> :toml
      _ -> :text
    end
  end

  defp format_size(bytes) when is_integer(bytes) and bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when is_integer(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(_), do: ""

  defp cm_language(:elixir), do: "elixir"
  defp cm_language(:markdown), do: "markdown"
  defp cm_language(:json), do: "json"
  defp cm_language(:bash), do: "shell"
  defp cm_language(:yaml), do: "yaml"
  defp cm_language(_), do: "text"

  # ── Tree-mode sidebar components ─────────────────────────────────────────────

  attr :entry, :map, required: true

  defp tree_item(assigns) do
    case assigns.entry.is_dir do
      true ->
        ~H"""
        <li>
          <details>
            <summary>
              <.icon name="hero-folder" class="w-4 h-4" />
              {@entry.name}
            </summary>
            <ul>
              <.tree_item :for={child <- @entry.children} entry={child} />
            </ul>
          </details>
        </li>
        """

      false ->
        ~H"""
        <li>
          <button
            phx-click="view_file"
            phx-value-path={@entry.path}
            class="flex items-center gap-2 w-full text-left"
          >
            <.icon name="hero-document" class="w-4 h-4" />
            <span class="truncate">{@entry.name}</span>
            <span class="badge badge-ghost badge-xs ml-auto shrink-0">{format_size(@entry.size)}</span>
          </button>
        </li>
        """
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
              <.icon name="hero-folder" class="w-4 h-4" /> Explore
            </button>
            <button
              class={"btn btn-sm join-item" <> if @view_mode == :list, do: " btn-active", else: ""}
              phx-click="toggle_view_mode"
              phx-value-mode="list"
            >
              <.icon name="hero-bars-3" class="w-4 h-4" /> List
            </button>
          </div>
        </div>
      </div>

      <%= if @view_mode == :tree do %>
        <!-- Tree View: sidebar + content -->
        <div class="h-[calc(100dvh-10rem)] flex flex-col md:flex-row">
          <!-- Sidebar -->
          <div
            id="config-tree-sidebar"
            class="w-full md:w-80 md:flex-shrink-0 border-b md:border-b-0 md:border-r border-base-300 bg-base-100 overflow-y-auto max-h-64 md:max-h-none"
            phx-update="ignore"
          >
            <div class="p-4">
              <h2 class="text-sm font-semibold text-base-content/80 mb-2 flex items-center gap-1">
                <.icon name="hero-cog-6-tooth" class="w-4 h-4" /> .claude/
              </h2>
              <ul class="menu menu-sm bg-base-200 rounded-lg">
                <.tree_item :for={entry <- @entries} entry={entry} />
              </ul>
            </div>
          </div>
          
    <!-- Content viewer -->
          <div class="flex-1 min-h-0 overflow-y-auto">
            <%= if @selected_file do %>
              <div class="p-6">
                <div class="card bg-base-100 border border-base-300 shadow-sm">
                  <div class="card-body p-0">
                    <div class="flex items-center justify-between px-4 py-2 border-b border-base-300 bg-base-200/50">
                      <code class="text-sm font-semibold text-base-content">{@selected_file}</code>
                      <div class="flex items-center gap-1">
                        <button
                          phx-click="open_file"
                          class="btn btn-ghost btn-xs"
                          title="Open in editor"
                        >
                          <.icon name="hero-pencil-square" class="w-3.5 h-3.5" /> Edit
                        </button>
                        <button phx-click="close_viewer" class="btn btn-ghost btn-xs btn-circle">
                          <.icon name="hero-x-mark" class="w-4 h-4" />
                        </button>
                      </div>
                    </div>
                    <div class="overflow-auto max-h-[calc(100dvh-18rem)]">
                      <%= if @file_type == :markdown do %>
                        <div
                          id="config-viewer"
                          class="dm-markdown p-4 text-sm text-base-content leading-relaxed"
                          phx-hook="MarkdownMessage"
                          data-raw-body={@file_content}
                        >
                        </div>
                      <% else %>
                        <div
                          id={"codemirror-#{Base.encode16(:crypto.hash(:md5, @selected_file), case: :lower)}"}
                          phx-hook="CodeMirror"
                          data-content={Base.encode64(@file_content)}
                          data-lang={cm_language(@file_type)}
                          class="min-h-[300px]"
                        />
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
            <% else %>
              <div class="flex items-center justify-center h-full">
                <div class="text-center">
                  <.icon
                    name="hero-document-text"
                    class="w-16 h-16 mx-auto text-base-content/20 mb-4"
                  />
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
              <div class="alert alert-error mb-4">
                <.icon name="hero-x-circle" class="shrink-0 h-6 w-6" />
                <span>{@error}</span>
              </div>
            <% end %>

            <%= if @file_content do %>
              <!-- File content -->
              <div class="mb-4">
                <div class="flex items-center gap-2 mb-4">
                  <.link
                    patch={
                      if @current_path && Path.dirname(@current_path) != ".",
                        do:
                          ~p"/projects/#{@project.id}/config?mode=list&path=#{Path.dirname(@current_path)}",
                        else: ~p"/projects/#{@project.id}/config?mode=list"
                    }
                    class="btn btn-sm btn-ghost"
                  >
                    <.icon name="hero-arrow-left" class="w-4 h-4" /> Back
                  </.link>
                  <div>
                    <h2 class="text-lg font-semibold text-base-content">
                      {Path.basename(@current_path)}
                    </h2>
                    <p class="text-sm text-base-content/60">.claude/{@current_path}</p>
                  </div>
                  <button
                    phx-click="open_file"
                    class="btn btn-sm btn-ghost ml-auto"
                    title="Open in editor"
                  >
                    <.icon name="hero-pencil-square" class="w-4 h-4" /> Edit
                  </button>
                </div>
                <div class="rounded-lg overflow-hidden">
                  <%= if @file_type == :markdown do %>
                    <div
                      id="config-viewer-list"
                      class="dm-markdown p-4 text-sm text-base-content leading-relaxed"
                      phx-hook="MarkdownMessage"
                      data-raw-body={@file_content}
                    >
                    </div>
                  <% else %>
                    <div
                      id={"codemirror-list-#{Base.encode16(:crypto.hash(:md5, @current_path), case: :lower)}"}
                      phx-hook="CodeMirror"
                      data-content={Base.encode64(@file_content)}
                      data-lang={cm_language(@file_type)}
                      class="min-h-[300px]"
                    />
                  <% end %>
                </div>
              </div>
            <% else %>
              <!-- Directory listing -->
              <%= if length(@files) > 0 do %>
                <div class="mb-4">
                  <%= if @current_path do %>
                    <.link
                      patch={
                        if Path.dirname(@current_path) != ".",
                          do:
                            ~p"/projects/#{@project.id}/config?mode=list&path=#{Path.dirname(@current_path)}",
                          else: ~p"/projects/#{@project.id}/config?mode=list"
                      }
                      class="btn btn-sm btn-ghost mb-4"
                    >
                      <.icon name="hero-arrow-left" class="w-4 h-4" /> Back
                    </.link>
                  <% end %>
                  <h2 class="text-lg font-semibold text-base-content mb-2">
                    .claude/{@current_path || ""}
                  </h2>
                </div>
                
    <!-- Mobile list -->
                <div class="md:hidden space-y-2">
                  <%= for file <- @files do %>
                    <.link
                      patch={~p"/projects/#{@project.id}/config?mode=list&path=#{file.path}"}
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
                          {if file.is_dir, do: "Directory", else: format_size(file.size)}
                        </p>
                      </div>
                    </.link>
                  <% end %>
                </div>
                
    <!-- Desktop table -->
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
                              patch={~p"/projects/#{@project.id}/config?mode=list&path=#{file.path}"}
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
                          <td class="text-right text-base-content/60">
                            {if file.is_dir, do: "", else: format_size(file.size)}
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% else %>
                <div class="flex items-center justify-center h-[calc(100dvh-20rem)]">
                  <div class="text-center">
                    <.icon
                      name="hero-document-text"
                      class="w-16 h-16 mx-auto text-base-content/20 mb-4"
                    />
                    <h3 class="text-lg font-semibold text-base-content/60 mb-2">Empty directory</h3>
                    <p class="text-sm text-base-content/40">No files in this directory</p>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      <% end %>
    <% else %>
      <div class="flex items-center justify-center h-[calc(100dvh-10rem)]">
        <div class="text-center py-12">
          <.icon name="hero-cog-6-tooth" class="mx-auto h-12 w-12 text-base-content/40" />
          <h3 class="mt-2 text-sm font-medium text-base-content">No .claude directory</h3>
          <p class="mt-1 text-sm text-base-content/60">
            <%= if @project && @project.path do %>
              No .claude directory found at {@project.path}
            <% else %>
              Project path not configured
            <% end %>
          </p>
        </div>
      </div>
    <% end %>
    """
  end
end
