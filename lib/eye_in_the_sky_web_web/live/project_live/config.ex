defmodule EyeInTheSkyWebWeb.ProjectLive.Config do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Projects
  alias EyeInTheSkyWeb.Repo

  @impl true
  def mount(%{"id" => id}, _session, socket) do
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

        tasks = Projects.get_project_tasks(project_id)
        claude_dir = if project.path, do: Path.join(project.path, ".claude"), else: nil

        socket
        |> assign(:page_title, "Config - #{project.name}")
        |> assign(:project, project)
        |> assign(:sidebar_tab, :config)
        |> assign(:sidebar_project, project)
        |> assign(:tasks, tasks)
        |> assign(:claude_dir, claude_dir)
        |> assign(:selected_file, nil)
        |> assign(:selected_file_path, nil)
        |> assign(:file_content, nil)
        |> assign(:file_type, nil)
        |> assign(:entries, [])
        |> load_claude_dir()
      else
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:tasks, [])
        |> assign(:claude_dir, nil)
        |> assign(:selected_file, nil)
        |> assign(:selected_file_path, nil)
        |> assign(:file_content, nil)
        |> assign(:file_type, nil)
        |> assign(:entries, [])
        |> put_flash(:error, "Invalid project ID")
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("view_file", %{"path" => path}, socket) do
    claude_dir = socket.assigns.claude_dir

    if claude_dir && String.starts_with?(path, claude_dir) do
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

    if path && claude_dir && String.starts_with?(path, claude_dir) && File.exists?(path) do
      System.cmd("open", [path])
    end

    {:noreply, socket}
  end

  defp load_claude_dir(socket) do
    claude_dir = socket.assigns.claude_dir

    if claude_dir && File.dir?(claude_dir) do
      entries = scan_directory(claude_dir, claude_dir)
      assign(socket, :entries, entries)
    else
      socket
    end
  end

  defp scan_directory(base_dir, current_dir) do
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
            children = scan_directory(base_dir, full)

            %{
              name: item,
              path: full,
              relative: relative,
              is_dir: true,
              children: children,
              count: length(children)
            }
          else
            size =
              case File.stat(full) do
                {:ok, %{size: s}} -> s
                _ -> 0
              end

            %{
              name: item,
              path: full,
              relative: relative,
              is_dir: false,
              size: size
            }
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

  defp language_class(:markdown), do: "markdown"
  defp language_class(:json), do: "json"
  defp language_class(:elixir), do: "elixir"
  defp language_class(:bash), do: "bash"
  defp language_class(:yaml), do: "yaml"
  defp language_class(:toml), do: "toml"
  defp language_class(_), do: "plaintext"

  attr :entry, :map, required: true

  defp dir_entry(assigns) do
    ~H"""
    <div class="collapse collapse-arrow border border-base-300 bg-base-100">
      <input type="checkbox" />
      <div class="collapse-title py-3 min-h-0">
        <div class="flex items-center gap-2">
          <.icon name="hero-folder" class="w-4 h-4 text-primary/60" />
          <code class="text-sm font-semibold text-base-content">{@entry.name}/</code>
          <span class="badge badge-ghost badge-xs ml-auto">{@entry.count}</span>
        </div>
      </div>
      <div class="collapse-content px-4 pb-3">
        <%= if length(@entry.children) > 0 do %>
          <div class="space-y-1">
            <%= for child <- @entry.children do %>
              <%= if child.is_dir do %>
                <div class="ml-2">
                  <.dir_entry entry={child} />
                </div>
              <% else %>
                <.file_entry entry={child} />
              <% end %>
            <% end %>
          </div>
        <% else %>
          <p class="text-xs text-base-content/40 italic">Empty directory</p>
        <% end %>
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true

  defp file_entry(assigns) do
    ~H"""
    <button
      phx-click="view_file"
      phx-value-path={@entry.path}
      class="flex items-center gap-2 py-1 px-2 rounded text-sm w-full text-left hover:bg-base-200 transition-colors"
    >
      <.icon name="hero-document" class="w-3.5 h-3.5 text-base-content/40" />
      <span class="font-mono text-xs">{@entry.name}</span>
      <span class="text-xs text-base-content/40 ml-auto">{format_size(@entry.size)}</span>
    </button>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-6xl mx-auto">
        <%= if @claude_dir && File.dir?(@claude_dir) do %>
          <div class={if @selected_file, do: "grid grid-cols-1 lg:grid-cols-2 gap-6", else: ""}>
            <!-- Left: .claude browser -->
            <div>
              <div class="flex items-center gap-2 mb-4">
                <.icon name="hero-cog-6-tooth" class="w-5 h-5 text-base-content/60" />
                <code class="text-sm text-base-content/60">.claude/</code>
              </div>
              
    <!-- Top-level files first -->
              <% {files, dirs} = Enum.split_with(@entries, &(!&1.is_dir)) %>
              <%= if length(files) > 0 do %>
                <div class="space-y-1 mb-4">
                  <%= for entry <- files do %>
                    <.file_entry entry={entry} />
                  <% end %>
                </div>
              <% end %>
              
    <!-- Directories -->
              <div class="space-y-3">
                <%= for entry <- dirs do %>
                  <.dir_entry entry={entry} />
                <% end %>
              </div>
            </div>
            
    <!-- Right: file viewer -->
            <%= if @selected_file do %>
              <div class="sticky top-20">
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
                    <div class="overflow-auto max-h-[70vh]">
                      <%= if @file_type == :markdown do %>
                        <div
                          id="config-viewer"
                          class="dm-markdown p-4 text-sm text-base-content leading-relaxed"
                          phx-hook="MarkdownMessage"
                          data-raw-body={@file_content}
                        >
                        </div>
                      <% else %>
                        <pre class="p-4 text-xs font-mono text-base-content whitespace-pre-wrap break-all"><code class={"language-#{language_class(@file_type)}"}>{@file_content}</code></pre>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
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
        <% end %>
      </div>
    </div>
    """
  end
end
