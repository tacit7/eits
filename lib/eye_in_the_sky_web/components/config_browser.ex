defmodule EyeInTheSkyWeb.Components.ConfigBrowser do
  @moduledoc """
  Rendering components for the .claude directory browser in ProjectLive.Config.
  Provides tree_view/1, list_view/1, and tree_item/1 function components,
  plus format_size/1 and language_class/1 helpers.
  """
  use EyeInTheSkyWeb, :html

  attr :entry, :map, required: true

  def tree_item(assigns) do
    if assigns.entry.is_dir, do: dir_item(assigns), else: file_item(assigns)
  end

  defp dir_item(assigns) do
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
  end

  defp file_item(assigns) do
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

  def tree_view(assigns) do
    ~H"""
    <div class="h-[calc(100dvh-10rem)] flex flex-col md:flex-row">
      <!-- Sidebar -->
      <div
        id="config-tree-sidebar"
        class="w-full md:w-80 md:flex-shrink-0 border-b md:border-b-0 md:border-r border-base-300 bg-base-100 overflow-y-auto max-h-[35dvh] md:max-h-none"
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
                      class="btn btn-ghost btn-sm min-h-[44px]"
                      title="Open in editor"
                    >
                      <.icon name="hero-pencil-square" class="w-3.5 h-3.5" /> Edit
                    </button>
                    <button phx-click="close_viewer" class="btn btn-ghost btn-sm btn-circle min-h-[44px] min-w-[44px]">
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
                    <pre class="p-4 text-xs font-mono text-base-content whitespace-pre-wrap break-all"><code class={"language-#{language_class(@file_type)}"}>{@file_content}</code></pre>
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
    """
  end

  def list_view(assigns) do
    ~H"""
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
    """
  end

  @doc "Returns the CSS language class string for a given file type atom."
  def language_class(:markdown), do: "markdown"
  def language_class(:json), do: "json"
  def language_class(:elixir), do: "elixir"
  def language_class(:bash), do: "bash"
  def language_class(:yaml), do: "yaml"
  def language_class(:toml), do: "toml"
  def language_class(_), do: "plaintext"

  @doc "Formats a byte count as a human-readable string."
  def format_size(bytes) when is_integer(bytes) and bytes < 1024, do: "#{bytes} B"
  def format_size(bytes) when is_integer(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"
  def format_size(_), do: ""
end
