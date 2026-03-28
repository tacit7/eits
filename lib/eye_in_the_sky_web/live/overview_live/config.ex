defmodule EyeInTheSkyWeb.OverviewLive.Config do
  use EyeInTheSkyWeb, :live_view

  @claude_dir Path.expand("~/.claude")

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Config")
      |> assign(:sidebar_tab, :config)
      |> assign(:sidebar_project, nil)
      |> assign(:claude_dir, @claude_dir)
      |> assign(:files, [])
      |> assign(:current_path, nil)
      |> assign(:selected_file, nil)
      |> assign(:selected_file_path, nil)
      |> assign(:file_content, nil)
      |> assign(:file_type, nil)
      |> assign(:error, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    path = Map.get(params, "path")
    {:noreply, load_list_path(socket, path)}
  end

  @impl true
  def handle_event("view_file", %{"path" => path}, socket) do
    if String.starts_with?(path, @claude_dir <> "/") do
      {:noreply, push_patch(socket, to: ~p"/config?path=#{relative_path(path)}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_file", _params, socket) do
    if path = socket.assigns.selected_file_path do
      if String.starts_with?(path, @claude_dir <> "/") do
        EyeInTheSkyWeb.Helpers.ViewHelpers.open_in_system(path)
      end
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_viewer", _params, socket) do
    path = socket.assigns.current_path

    target =
      if path && Path.dirname(path) != ".",
        do: ~p"/config?path=#{Path.dirname(path)}",
        else: ~p"/config"

    {:noreply, push_patch(socket, to: target)}
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  defp load_list_path(socket, path) do
    unless File.dir?(@claude_dir) do
      assign(socket, :error, "~/.claude directory not found")
    else
      target =
        if path && path != "" do
          full = Path.join(@claude_dir, path)
          expanded_base = Path.expand(@claude_dir)
          expanded_full = Path.expand(full)

          if String.starts_with?(expanded_full, expanded_base <> "/"),
            do: {:ok, full, path},
            else: {:error, "Access denied"}
        else
          {:ok, @claude_dir, nil}
        end

      case target do
        {:error, msg} ->
          assign(socket, :error, msg)

        {:ok, full_path, rel_path} ->
          cond do
            File.dir?(full_path) ->
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
                    |> Enum.sort_by(&sort_key/1)

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

            File.regular?(full_path) ->
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

            true ->
              assign(socket, :error, "Path not found: #{path}")
          end
      end
    end
  end

  @pinned_order ~w(CLAUDE.md settings.json commands agents skills)

  defp sort_key(%{name: name} = entry) do
    idx = Enum.find_index(@pinned_order, &(String.downcase(&1) == String.downcase(name)))
    pinned = if idx, do: {0, idx}, else: {1, 0}
    {pinned, !entry.is_dir, String.downcase(name)}
  end

  defp relative_path(path) do
    String.replace_prefix(path, @claude_dir <> "/", "")
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

  @impl true
  def render(assigns) do
    ~H"""
    <%= if File.dir?(@claude_dir) do %>
      <!-- Toolbar -->
      <div class="bg-base-100 border-b border-base-300">
        <div class="px-4 sm:px-6 lg:px-8 py-2 flex items-center gap-2">
          <button
            id="config-guide-chat-btn"
            phx-hook="ConfigChatGuide"
            class="btn btn-sm btn-ghost ml-auto"
          >
            <.icon name="hero-chat-bubble-left-ellipsis" class="w-4 h-4" /> Config Guide
          </button>
        </div>
      </div>

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
                      do: ~p"/config?path=#{Path.dirname(@current_path)}",
                      else: ~p"/config"
                  }
                  class="btn btn-sm btn-ghost"
                >
                  <.icon name="hero-arrow-left" class="w-4 h-4" /> Back
                </.link>
                <div>
                  <h2 class="text-lg font-semibold text-base-content">
                    {Path.basename(@current_path)}
                  </h2>
                  <p class="text-sm text-base-content/60">~/.claude/{@current_path}</p>
                </div>
                <button
                  phx-click="open_file"
                  class="btn btn-sm btn-ghost ml-auto"
                  title="Open in editor"
                >
                  <.icon name="hero-pencil-square" class="w-4 h-4" /> Edit
                </button>
              </div>
              <div class="bg-base-200 rounded-lg overflow-x-auto">
                <%= if @file_type == :markdown do %>
                  <div
                    id="config-viewer-list"
                    class="dm-markdown p-4 text-sm text-base-content leading-relaxed"
                    phx-hook="MarkdownMessage"
                    data-raw-body={@file_content}
                  >
                  </div>
                <% else %>
                  <pre class="text-sm p-4"><code id="code-viewer" class={"language-#{language_class(@file_type)}"} phx-hook="Highlight"><%= @file_content %></code></pre>
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
                        do: ~p"/config?path=#{Path.dirname(@current_path)}",
                        else: ~p"/config"
                    }
                    class="btn btn-sm btn-ghost mb-4"
                  >
                    <.icon name="hero-arrow-left" class="w-4 h-4" /> Back
                  </.link>
                <% end %>
                <h2 class="text-lg font-semibold text-base-content mb-2">
                  ~/.claude/{@current_path || ""}
                </h2>
              </div>

              <!-- Mobile list -->
              <div class="md:hidden space-y-2">
                <%= for file <- @files do %>
                  <.link
                    patch={~p"/config?path=#{file.path}"}
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
                            patch={~p"/config?path=#{file.path}"}
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
    <% else %>
      <div class="flex items-center justify-center h-[calc(100dvh-10rem)]">
        <div class="text-center py-12">
          <.icon name="hero-cog-6-tooth" class="mx-auto h-12 w-12 text-base-content/40" />
          <h3 class="mt-2 text-sm font-medium text-base-content">No ~/.claude directory found</h3>
          <p class="mt-1 text-sm text-base-content/60">
            Install Claude Code and run it once to initialize the config directory.
          </p>
        </div>
      </div>
    <% end %>
    """
  end
end
