defmodule EyeInTheSkyWeb.Live.FileBrowserHelpers do
  @moduledoc """
  Shared helpers for file-browser LiveViews.

  Provides:
  - `file_listing/1` — responsive mobile-card / desktop-table directory listing component
  - `read_file_for_display/4` — socket-aware file reader shared by OverviewLive.Config
    and ProjectLive.Config

  Pure I/O helpers (path_within?, list_directory, dispatch_path, build_file_entry, etc.)
  live in `EyeInTheSkyWeb.Helpers.ProjectFileBrowserHelpers`.
  """
  use EyeInTheSkyWeb, :html

  import EyeInTheSkyWeb.Helpers.ProjectFileBrowserHelpers, only: [assign_file_read: 4]
  import EyeInTheSkyWeb.Helpers.FileHelpers, only: [format_size: 1]

  # ── Rendering component ───────────────────────────────────────────────────────

  @doc """
  Renders a responsive file listing.

  Expects each entry in `files` to have:
  - `:name`   — display name (string)
  - `:path`   — path value passed to `patch_fn` (string)
  - `:is_dir` — boolean
  - `:size`   — integer byte count (0 for directories)

  `patch_fn` is called as `patch_fn.(file.path)` to produce the `patch` URL for
  each link. Pass an anonymous function, e.g.:

      patch_fn={fn path -> ~p"/config?path=\#{path}" end}
  """
  attr :files, :list, required: true
  attr :patch_fn, :any, required: true

  def file_listing(assigns) do
    ~H"""
    <!-- Mobile list -->
    <div class="md:hidden space-y-2">
      <%= for file <- @files do %>
        <.link
          patch={@patch_fn.(file.path)}
          class="flex items-center gap-3 rounded-lg border border-base-content/10 bg-base-100 px-3 py-2"
        >
          <%= if file.is_dir do %>
            <.icon name="hero-folder-solid" class="size-4 text-primary shrink-0" />
          <% else %>
            <.icon name="hero-document" class="size-4 shrink-0" />
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
                <.link patch={@patch_fn.(file.path)} class="flex items-center gap-2">
                  <%= if file.is_dir do %>
                    <.icon name="hero-folder-solid" class="size-4 text-primary" />
                  <% else %>
                    <.icon name="hero-document" class="size-4" />
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
    """
  end

  # ── Socket helper ─────────────────────────────────────────────────────────────

  @doc """
  Reads a file and assigns its content to the socket.

  On success: sets `:file_content`, `:file_type`, `:selected_file`,
  `:selected_file_path`, `:current_path`, clears `:files` and `:error`.

  On error (too large, stat failure, read failure): only sets `:error`.
  Existing `:files` and `:current_path` are **preserved** so callers that
  show a directory listing keep it visible after a transient file read error.

  Callers that need different error-state behavior (e.g. always clearing the
  listing) should pipe additional `assign/3` calls after this function.
  """
  def read_file_for_display(socket, full_path, rel_path, base_dir) do
    case assign_file_read(socket, full_path, rel_path, base_dir) do
      {:ok, sock} ->
        sock
        |> assign(:current_path, rel_path)
        |> assign(:files, [])

      {:error, sock} ->
        sock
    end
  end
end
