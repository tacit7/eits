defmodule EyeInTheSkyWebWeb.OverviewLive.Config do
  use EyeInTheSkyWebWeb, :live_view

  @claude_dir Path.expand("~/.claude")

  @config_files [
    {"CLAUDE.md", "Global instructions for all projects"},
    {"settings.json", "Claude Code settings"},
    {"mcp.json", "MCP server configuration"},
    {".mcp.json", "Hidden MCP configuration"}
  ]

  @config_dirs [
    {"commands", "Slash commands / skills"},
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
      |> assign(:files, files)
      |> assign(:dirs, dirs)
      |> assign(:selected_file, nil)
      |> assign(:selected_file_path, nil)
      |> assign(:file_content, nil)

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
          case File.ls(path) do
            {:ok, items} ->
              items
              |> Enum.reject(&String.starts_with?(&1, "."))
              |> Enum.sort()
              |> Enum.map(fn item ->
                full = Path.join(path, item)
                is_dir = File.dir?(full)

                size =
                  if is_dir do
                    case File.ls(full) do
                      {:ok, children} -> length(children)
                      _ -> 0
                    end
                  else
                    case File.stat(full) do
                      {:ok, %{size: s}} -> s
                      _ -> 0
                    end
                  end

                %{name: item, path: full, is_dir: is_dir, size: size}
              end)

            _ ->
              []
          end
        else
          []
        end

      %{name: name, description: desc, path: path, exists: exists, entries: entries}
    end)
  end

  defp relative_path(path) do
    String.replace_prefix(path, @claude_dir <> "/", "")
  end

  defp format_size(bytes) when is_integer(bytes) and bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when is_integer(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component module={EyeInTheSkyWebWeb.Components.Navbar} id="navbar" />
    <EyeInTheSkyWebWeb.Components.OverviewNav.render current_tab={:config} />

    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-6xl mx-auto">
        <div class={if @selected_file, do: "grid grid-cols-1 lg:grid-cols-2 gap-6", else: ""}>
          <!-- Left: file browser -->
          <div>
            <!-- Config Files -->
            <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-3">
              Config Files
            </h2>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-8">
              <%= for file <- @files do %>
                <button
                  phx-click="view_file"
                  phx-value-path={file.path}
                  disabled={!file.exists}
                  class={"card bg-base-100 border border-base-300 shadow-sm text-left transition-all #{if file.exists, do: "hover:border-primary cursor-pointer", else: "opacity-40 cursor-not-allowed"} #{if @selected_file == file.name, do: "border-primary ring-1 ring-primary"}"}
                >
                  <div class="card-body p-3">
                    <div class="flex items-center gap-2">
                      <svg class="w-4 h-4 text-base-content/50 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                      </svg>
                      <code class="text-sm font-semibold text-base-content">{file.name}</code>
                      <%= if file.exists do %>
                        <span class="text-xs text-base-content/40 ml-auto">{format_size(file.size)}</span>
                      <% else %>
                        <span class="badge badge-ghost badge-xs ml-auto">missing</span>
                      <% end %>
                    </div>
                    <p class="text-xs text-base-content/60 mt-1">{file.description}</p>
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
                <div class={"collapse collapse-arrow border border-base-300 bg-base-100 #{if !dir.exists, do: "opacity-40"}"}>
                  <input type="checkbox" />
                  <div class="collapse-title py-3 min-h-0">
                    <div class="flex items-center gap-2">
                      <svg class="w-4 h-4 text-primary/60 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z" />
                      </svg>
                      <code class="text-sm font-semibold text-base-content">{dir.name}/</code>
                      <span class="text-xs text-base-content/40">{dir.description}</span>
                      <span class="badge badge-ghost badge-xs ml-auto">{length(dir.entries)}</span>
                    </div>
                  </div>
                  <div class="collapse-content px-4 pb-3">
                    <%= if length(dir.entries) > 0 do %>
                      <div class="space-y-1">
                        <%= for entry <- dir.entries do %>
                          <%= if entry.is_dir do %>
                            <div class="flex items-center gap-2 py-1 px-2 rounded text-sm text-base-content/70">
                              <svg class="w-3.5 h-3.5 text-primary/40" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z" />
                              </svg>
                              <span class="font-mono text-xs">{entry.name}/</span>
                              <span class="text-xs text-base-content/40 ml-auto">{entry.size} items</span>
                            </div>
                          <% else %>
                            <button
                              phx-click="view_file"
                              phx-value-path={entry.path}
                              class={"flex items-center gap-2 py-1 px-2 rounded text-sm w-full text-left hover:bg-base-200 transition-colors #{if @selected_file == relative_path(entry.path), do: "bg-base-200 text-primary"}"}
                            >
                              <svg class="w-3.5 h-3.5 text-base-content/40" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                              </svg>
                              <span class="font-mono text-xs">{entry.name}</span>
                              <span class="text-xs text-base-content/40 ml-auto">{format_size(entry.size)}</span>
                            </button>
                          <% end %>
                        <% end %>
                      </div>
                    <% else %>
                      <p class="text-xs text-base-content/40 italic">Empty directory</p>
                    <% end %>
                  </div>
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
                      <button phx-click="open_file" class="btn btn-ghost btn-xs" title="Open in editor">
                        <.icon name="hero-pencil-square" class="w-3.5 h-3.5" /> Edit
                      </button>
                      <button phx-click="close_viewer" class="btn btn-ghost btn-xs btn-circle">
                        <.icon name="hero-x-mark" class="w-4 h-4" />
                      </button>
                    </div>
                  </div>
                  <div class="overflow-auto max-h-[70vh]">
                    <%= if String.ends_with?(@selected_file, ".json") do %>
                      <pre class="p-4 text-xs font-mono text-base-content whitespace-pre-wrap break-all"><code>{@file_content}</code></pre>
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
