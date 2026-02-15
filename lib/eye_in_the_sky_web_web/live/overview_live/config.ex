defmodule EyeInTheSkyWebWeb.OverviewLive.Config do
  use EyeInTheSkyWebWeb, :live_view

  @claude_dir Path.expand("~/.claude")

  @config_files [
    {"CLAUDE.md", "Global instructions for all projects"},
    {"settings.json", "Claude Code settings"}
  ]

  @config_dirs [
    {"commands", "Slash commands / skills"},
    {"skills", "Reusable skills"},
    {"agents", "Agent definitions"},
    {"hooks", "Event hooks (shell scripts)"},
    {"projects", "Per-project session data"},
    {"plans", "Saved plans"},
    {"ide", "IDE integration config"},
    {"plugins", "Plugins"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    files = load_config_files()
    dirs = load_config_dirs()

    socket =
      socket
      |> assign(:page_title, "Config")
      |> assign(:sidebar_tab, :config)
      |> assign(:sidebar_project, nil)
      |> assign(:files, files)
      |> assign(:dirs, dirs)
      |> assign(:selected_file, nil)
      |> assign(:selected_file_path, nil)
      |> assign(:file_content, nil)
      |> assign(:expanded_dirs, MapSet.new())

    {:ok, socket}
  end

  @impl true
  def handle_event("view_file", %{"path" => path}, socket) do
    # Only allow reading files under ~/.claude
    if String.starts_with?(path, @claude_dir) do
      content =
        case File.read(path) do
          {:ok, data} -> data
          {:error, _} -> "Error: could not read file"
        end

      {:noreply,
       socket
       |> assign(:selected_file, relative_path(path))
       |> assign(:selected_file_path, path)
       |> assign(:file_content, content)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_dir", %{"path" => path}, socket) do
    expanded_dirs =
      if MapSet.member?(socket.assigns.expanded_dirs, path) do
        MapSet.delete(socket.assigns.expanded_dirs, path)
      else
        MapSet.put(socket.assigns.expanded_dirs, path)
      end

    {:noreply, assign(socket, :expanded_dirs, expanded_dirs)}
  end

  @impl true
  def handle_event("close_viewer", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_file, nil)
     |> assign(:selected_file_path, nil)
     |> assign(:file_content, nil)}
  end

  @impl true
  def handle_event("open_file", _params, socket) do
    path = socket.assigns.selected_file_path

    if path && String.starts_with?(path, @claude_dir) && File.exists?(path) do
      System.cmd("open", [path])
    end

    {:noreply, socket}
  end

  defp load_config_files do
    @config_files
    |> Enum.map(fn {name, desc} ->
      path = Path.join(@claude_dir, name)
      exists = File.exists?(path)

      size =
        if exists do
          case File.stat(path) do
            {:ok, %{size: s}} -> s
            _ -> 0
          end
        else
          0
        end

      %{name: name, description: desc, path: path, exists: exists, size: size}
    end)
  end

  defp load_config_dirs do
    @config_dirs
    |> Enum.map(fn {name, desc} ->
      path = Path.join(@claude_dir, name)
      exists = File.dir?(path)

      entries =
        if exists do
          load_dir_entries(path)
        else
          []
        end

      %{name: name, description: desc, path: path, exists: exists, entries: entries}
    end)
  end

  defp load_dir_entries(path) do
    case File.ls(path) do
      {:ok, items} ->
        items
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.sort()
        |> Enum.map(fn item ->
          full = Path.join(path, item)
          is_dir = File.dir?(full)

          if is_dir do
            # Recursively load subdirectories
            children = load_dir_entries(full)
            %{name: item, path: full, is_dir: true, children: children}
          else
            size =
              case File.stat(full) do
                {:ok, %{size: s}} -> s
                _ -> 0
              end

            %{name: item, path: full, is_dir: false, size: size}
          end
        end)

      _ ->
        []
    end
  end

  defp relative_path(path) do
    String.replace_prefix(path, @claude_dir <> "/", "")
  end

  defp format_size(bytes) when is_integer(bytes) and bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when is_integer(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(_), do: ""

  defp render_entries(assigns) do
    ~H"""
    <div class="space-y-1">
      <%= for entry <- @entries do %>
        <%= if entry.is_dir do %>
          <% is_expanded = MapSet.member?(@expanded_dirs, entry.path) %>
          <div class="border border-base-300/50 bg-base-100/50 my-1">
            <div
              class="py-2 px-2 cursor-pointer hover:bg-base-200/50 transition-colors flex items-center justify-between"
              phx-click="toggle_dir"
              phx-value-path={entry.path}
            >
              <div class="flex items-center gap-2">
                <.icon name="hero-folder" class="w-3.5 h-3.5 text-primary/40 shrink-0" />
                <span class="font-mono text-xs">{entry.name}/</span>
                <span class="badge badge-ghost badge-xs">{length(entry.children)}</span>
              </div>
              <.icon
                name="hero-chevron-right"
                class={"w-4 h-4 text-base-content/40 transition-transform #{if is_expanded, do: "rotate-90"}"}
              />
            </div>
            <%= if is_expanded do %>
              <div class="px-2 pb-2">
                <%= if length(entry.children) > 0 do %>
                  {render_entries(assign(assigns, :entries, entry.children))}
                <% else %>
                  <p class="text-xs text-base-content/40 italic px-2">Empty directory</p>
                <% end %>
              </div>
            <% end %>
          </div>
        <% else %>
          <button
            phx-click="view_file"
            phx-value-path={entry.path}
            class={"flex items-center gap-2 py-1 px-2 rounded text-sm w-full text-left hover:bg-base-200 transition-colors #{if @selected_file == relative_path(entry.path), do: "bg-base-200 text-primary"}"}
          >
            <.icon name="hero-document-text" class="w-3.5 h-3.5 text-base-content/40 shrink-0" />
            <span class="font-mono text-xs">{entry.name}</span>
            <span class="text-xs text-base-content/40 ml-auto">{format_size(entry.size)}</span>
          </button>
        <% end %>
      <% end %>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-6xl mx-auto">
        <div class={if @selected_file, do: "grid grid-cols-1 lg:grid-cols-2 gap-6", else: ""}>
          <!-- Left: file browser -->
          <div>
            <!-- Config Files -->
            <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-3">
              Config Files
            </h2>
            <div class="space-y-3 mb-8">
              <%= for file <- @files do %>
                <button
                  phx-click="view_file"
                  phx-value-path={file.path}
                  disabled={!file.exists}
                  class={"border border-base-300 bg-base-100 text-left transition-all w-full #{if file.exists, do: "hover:border-primary cursor-pointer", else: "opacity-40 cursor-not-allowed"} #{if @selected_file == file.name, do: "border-primary ring-1 ring-primary"}"}
                >
                  <div class="py-3 px-4">
                    <div class="flex items-center gap-2">
                      <.icon name="hero-document-text" class="w-4 h-4 text-base-content/50 shrink-0" />
                      <code class="text-sm font-semibold text-base-content">{file.name}</code>
                      <span class="text-xs text-base-content/40">{file.description}</span>
                      <%= if file.exists do %>
                        <span class="text-xs text-base-content/40 ml-auto">
                          {format_size(file.size)}
                        </span>
                      <% else %>
                        <span class="badge badge-ghost badge-xs ml-auto">missing</span>
                      <% end %>
                    </div>
                  </div>
                </button>
              <% end %>
            </div>
            
    <!-- Directories -->
            <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-3">
              Directories
            </h2>
            <div class="space-y-3">
              <%= for dir <- @dirs do %>
                <% is_expanded = MapSet.member?(@expanded_dirs, dir.path) %>
                <div class={"border border-base-300 bg-base-100 #{if !dir.exists, do: "opacity-40"}"}>
                  <div
                    class="py-3 px-4 cursor-pointer hover:bg-base-200/50 transition-colors flex items-center justify-between"
                    phx-click="toggle_dir"
                    phx-value-path={dir.path}
                  >
                    <div class="flex items-center gap-2">
                      <.icon name="hero-folder" class="w-4 h-4 text-primary/60 shrink-0" />
                      <code class="text-sm font-semibold text-base-content">{dir.name}/</code>
                      <span class="text-xs text-base-content/40">{dir.description}</span>
                      <span class="badge badge-ghost badge-xs ml-auto">{length(dir.entries)}</span>
                    </div>
                    <.icon
                      name="hero-chevron-right"
                      class={"w-4 h-4 text-base-content/40 transition-transform #{if is_expanded, do: "rotate-90"}"}
                    />
                  </div>
                  <%= if is_expanded do %>
                    <div class="px-4 pb-3">
                      <%= if length(dir.entries) > 0 do %>
                        {render_entries(assign(assigns, :entries, dir.entries))}
                      <% else %>
                        <p class="text-xs text-base-content/40 italic">Empty directory</p>
                      <% end %>
                    </div>
                  <% end %>
                </div>
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
                    <%= if String.ends_with?(@selected_file, ".json") do %>
                      <pre
                        id="json-viewer"
                        class="p-4 text-xs font-mono whitespace-pre-wrap break-all"
                        phx-hook="Highlight"
                      ><code class="language-json">{@file_content}</code></pre>
                    <% else %>
                      <div
                        id="config-viewer"
                        class="dm-markdown p-4 text-sm text-base-content leading-relaxed"
                        phx-hook="MarkdownMessage"
                        data-raw-body={@file_content}
                      >
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
