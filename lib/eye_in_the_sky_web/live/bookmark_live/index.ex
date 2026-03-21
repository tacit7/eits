defmodule EyeInTheSkyWeb.BookmarkLive.Index do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Bookmarks

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Bookmarks")
      |> assign(:filter_type, nil)
      |> assign(:filter_category, nil)
      |> assign(:sidebar_tab, :sessions)
      |> assign(:sidebar_project, nil)
      |> load_bookmarks()

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_type", %{"type" => type}, socket) do
    filter_type = if type == "", do: nil, else: type

    socket =
      socket
      |> assign(:filter_type, filter_type)
      |> load_bookmarks()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_category", %{"category" => category}, socket) do
    filter_category = if category == "", do: nil, else: category

    socket =
      socket
      |> assign(:filter_category, filter_category)
      |> load_bookmarks()

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    bookmark = Bookmarks.get_bookmark!(id)
    {:ok, _} = Bookmarks.delete_bookmark(bookmark)

    socket = load_bookmarks(socket)

    {:noreply, socket}
  end

  defp load_bookmarks(socket) do
    bookmarks =
      Bookmarks.list_bookmarks(
        bookmark_type: socket.assigns.filter_type,
        category: socket.assigns.filter_category
      )

    assign(socket, :bookmarks, bookmarks)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-6">
      <div class="max-w-7xl mx-auto">
        <!-- Header -->
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-3xl font-bold text-base-content">Bookmarks</h1>
            <p class="text-sm text-base-content/60 mt-1">
              Your saved files, notes, agents, and more
            </p>
          </div>

          <div class="flex items-center gap-2">
            <!-- Type Filter -->
            <select
              class="select select-bordered select-sm"
              phx-change="filter_type"
              name="type"
            >
              <option value="">All Types</option>
              <option value="file">Files</option>
              <option value="note">Notes</option>
              <option value="agent">Agents</option>
              <option value="session">Sessions</option>
              <option value="task">Tasks</option>
              <option value="url">URLs</option>
            </select>
            
    <!-- Category Filter -->
            <select
              class="select select-bordered select-sm"
              phx-change="filter_category"
              name="category"
            >
              <option value="">All Categories</option>
              <option value="important">Important</option>
              <option value="review-later">Review Later</option>
              <option value="bugs">Bugs</option>
              <option value="ideas">Ideas</option>
              <option value="docs">Documentation</option>
            </select>
          </div>
        </div>
        
    <!-- Bookmarks List -->
        <%= if length(@bookmarks) == 0 do %>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body text-center py-12">
              <.icon name="hero-bookmark" class="w-16 h-16 mx-auto text-base-content/20 mb-4" />
              <h3 class="text-lg font-semibold text-base-content/60">No bookmarks yet</h3>
              <p class="text-sm text-base-content/40 mt-2">
                Start bookmarking files, notes, and other items to find them quickly later
              </p>
            </div>
          </div>
        <% else %>
          <div class="space-y-2">
            <%= for bookmark <- @bookmarks do %>
              <div class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow">
                <div class="card-body p-4">
                  <div class="flex items-start justify-between gap-4">
                    <!-- Bookmark Icon -->
                    <div class="flex-shrink-0">
                      {bookmark_type_icon(bookmark.bookmark_type)}
                    </div>
                    
    <!-- Content -->
                    <div class="flex-1 min-w-0">
                      <!-- Badges -->
                      <div class="flex items-center gap-2 mb-2">
                        <span class="badge badge-sm">{bookmark.bookmark_type}</span>
                        <%= if bookmark.category do %>
                          <span class="badge badge-sm badge-outline">{bookmark.category}</span>
                        <% end %>
                        <%= if bookmark.priority && bookmark.priority > 0 do %>
                          <span class="badge badge-sm badge-warning">P{bookmark.priority}</span>
                        <% end %>
                      </div>
                      
    <!-- Title -->
                      <h3 class="font-semibold text-base-content">
                        {bookmark.title || bookmark_display_text(bookmark)}
                      </h3>
                      
    <!-- Description -->
                      <%= if bookmark.description do %>
                        <p class="text-sm text-base-content/60 mt-1">{bookmark.description}</p>
                      <% end %>
                      
    <!-- Details -->
                      <div class="text-xs text-base-content/40 mt-2 font-mono">
                        {bookmark_details(bookmark)}
                      </div>
                      
    <!-- Timestamp -->
                      <div class="text-xs text-base-content/30 mt-2">
                        Created {format_timestamp(bookmark.inserted_at)}
                        <%= if bookmark.accessed_at do %>
                          • Last accessed {format_timestamp(bookmark.accessed_at)}
                        <% end %>
                      </div>
                    </div>
                    
    <!-- Actions -->
                    <div class="flex-shrink-0">
                      <button
                        phx-click="delete"
                        phx-value-id={bookmark.id}
                        class="btn btn-ghost btn-sm btn-square"
                        title="Remove bookmark"
                      >
                        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                          <path
                            fill-rule="evenodd"
                            d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z"
                            clip-rule="evenodd"
                          />
                        </svg>
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper functions

  defp bookmark_type_icon(type) do
    case type do
      "file" ->
        assigns = %{}

        ~H"""
        <svg class="w-5 h-5 text-primary" fill="currentColor" viewBox="0 0 20 20">
          <path
            fill-rule="evenodd"
            d="M4 4a2 2 0 012-2h4.586A2 2 0 0112 2.586L15.414 6A2 2 0 0116 7.414V16a2 2 0 01-2 2H6a2 2 0 01-2-2V4z"
            clip-rule="evenodd"
          />
        </svg>
        """

      "note" ->
        assigns = %{}

        ~H"""
        <svg class="w-5 h-5 text-secondary" fill="currentColor" viewBox="0 0 20 20">
          <path d="M9 2a1 1 0 000 2h2a1 1 0 100-2H9z" />
          <path
            fill-rule="evenodd"
            d="M4 5a2 2 0 012-2 3 3 0 003 3h2a3 3 0 003-3 2 2 0 012 2v11a2 2 0 01-2 2H6a2 2 0 01-2-2V5zm3 4a1 1 0 000 2h.01a1 1 0 100-2H7zm3 0a1 1 0 000 2h3a1 1 0 100-2h-3zm-3 4a1 1 0 100 2h.01a1 1 0 100-2H7zm3 0a1 1 0 100 2h3a1 1 0 100-2h-3z"
            clip-rule="evenodd"
          />
        </svg>
        """

      "agent" ->
        assigns = %{}

        ~H"""
        <svg class="w-5 h-5 text-accent" fill="currentColor" viewBox="0 0 20 20">
          <path
            fill-rule="evenodd"
            d="M10 9a3 3 0 100-6 3 3 0 000 6zm-7 9a7 7 0 1114 0H3z"
            clip-rule="evenodd"
          />
        </svg>
        """

      "url" ->
        assigns = %{}

        ~H"""
        <svg class="w-5 h-5 text-info" fill="currentColor" viewBox="0 0 20 20">
          <path
            fill-rule="evenodd"
            d="M12.586 4.586a2 2 0 112.828 2.828l-3 3a2 2 0 01-2.828 0 1 1 0 00-1.414 1.414 4 4 0 005.656 0l3-3a4 4 0 00-5.656-5.656l-1.5 1.5a1 1 0 101.414 1.414l1.5-1.5zm-5 5a2 2 0 012.828 0 1 1 0 101.414-1.414 4 4 0 00-5.656 0l-3 3a4 4 0 105.656 5.656l1.5-1.5a1 1 0 10-1.414-1.414l-1.5 1.5a2 2 0 11-2.828-2.828l3-3z"
            clip-rule="evenodd"
          />
        </svg>
        """

      _ ->
        assigns = %{}

        ~H"""
        <svg class="w-5 h-5 text-base-content/40" fill="currentColor" viewBox="0 0 20 20">
          <path
            fill-rule="evenodd"
            d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z"
            clip-rule="evenodd"
          />
        </svg>
        """
    end
  end

  defp bookmark_display_text(bookmark) do
    case bookmark.bookmark_type do
      "file" -> Path.basename(bookmark.file_path || "")
      "url" -> bookmark.url
      _ -> bookmark.bookmark_id || "Untitled"
    end
  end

  defp bookmark_details(bookmark) do
    case bookmark.bookmark_type do
      "file" ->
        if bookmark.line_number do
          "#{bookmark.file_path}:#{bookmark.line_number}"
        else
          bookmark.file_path
        end

      "url" ->
        bookmark.url

      _ ->
        "ID: #{bookmark.bookmark_id}"
    end
  end

  defp format_timestamp(nil), do: "never"

  defp format_timestamp(timestamp) do
    Calendar.strftime(timestamp, "%b %d, %Y at %I:%M %p")
  end
end
