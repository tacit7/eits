defmodule EyeInTheSkyWeb.PromptLive.Index do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Prompts
  import EyeInTheSkyWeb.Helpers.ViewHelpers

  @impl true
  def mount(_params, _session, socket) do
    prompts = Prompts.list_prompts()

    socket =
      socket
      |> assign(:page_title, "Subagent Prompts")
      |> assign(:prompts, prompts)
      |> assign(:scope_filter, "all")
      |> assign(:search_query, "")
      |> assign(:filtered_prompts, prompts)
      |> assign(:sidebar_tab, :prompts)
      |> assign(:sidebar_project, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    effective_query = if String.length(String.trim(query)) >= 4, do: query, else: ""

    socket =
      socket
      |> assign(:search_query, effective_query)
      |> update_filtered_prompts()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_scope", %{"scope" => scope}, socket) do
    socket =
      socket
      |> assign(:scope_filter, scope)
      |> update_filtered_prompts()

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    prompt = Prompts.get_prompt_by_uuid!(id)

    case Prompts.deactivate_prompt(prompt) do
      {:ok, _prompt} ->
        prompts = Prompts.list_prompts()

        socket =
          socket
          |> assign(:prompts, prompts)
          |> update_filtered_prompts()
          |> put_flash(:info, "Prompt deactivated successfully")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to deactivate prompt")}
    end
  end

  defp update_filtered_prompts(socket) do
    filtered = filter_prompts(socket.assigns)
    assign(socket, :filtered_prompts, filtered)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Subagent Prompts")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <div class="sm:flex sm:items-center sm:justify-between">
        <div class="sm:flex-auto">
          <h1 class="text-base font-semibold leading-6 text-gray-900 dark:text-gray-100">
            Subagent Prompts
          </h1>
          <p class="mt-2 text-sm text-gray-700 dark:text-gray-400">
            Reusable prompt templates for spawning specialized subagents
          </p>
        </div>
        <div class="mt-4 sm:mt-0 flex items-center gap-2">
          <.link navigate={~p"/prompts/new"} class="btn btn-primary btn-sm gap-2">
            <.icon name="hero-plus" class="h-4 w-4" /> New Prompt
          </.link>
          <label class="swap swap-rotate btn btn-ghost btn-sm btn-circle">
            <input type="checkbox" class="theme-controller" value="dark" />
            <!-- sun icon -->
            <svg class="swap-on h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z"
              />
            </svg>
            <!-- moon icon -->
            <svg class="swap-off h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z"
              />
            </svg>
          </label>
        </div>
      </div>
      
    <!-- Search and Filters -->
      <div class="mt-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:gap-6">
        <!-- Search -->
        <div class="flex-1 max-w-md">
          <label for="search" class="sr-only">Search prompts</label>
          <div class="relative">
            <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
              <svg class="h-5 w-5 text-gray-400" viewBox="0 0 20 20" fill="currentColor">
                <path
                  fill-rule="evenodd"
                  d="M9 3.5a5.5 5.5 0 100 11 5.5 5.5 0 000-11zM2 9a7 7 0 1112.452 4.391l3.328 3.329a.75.75 0 11-1.06 1.06l-3.329-3.328A7 7 0 012 9z"
                  clip-rule="evenodd"
                />
              </svg>
            </div>
            <input
              type="text"
              name="search"
              id="search"
              phx-keyup="search"
              phx-debounce="300"
              value={@search_query}
              class="input input-bordered w-full pl-10"
              placeholder="Search prompts by name, slug, or description..."
            />
          </div>
        </div>
        
    <!-- Scope Filter -->
        <div class="btn-group">
          <button
            phx-click="filter_scope"
            phx-value-scope="all"
            class={"btn btn-sm #{if @scope_filter == "all", do: "btn-active"}"}
          >
            All
          </button>
          <button
            phx-click="filter_scope"
            phx-value-scope="global"
            class={"btn btn-sm #{if @scope_filter == "global", do: "btn-active"}"}
          >
            Global
          </button>
          <button
            phx-click="filter_scope"
            phx-value-scope="project"
            class={"btn btn-sm #{if @scope_filter == "project", do: "btn-active"}"}
          >
            Project
          </button>
        </div>
      </div>

      <div class="mt-6 overflow-x-auto">
        <table class="table table-zebra table-pin-rows">
          <thead>
            <tr>
              <th>Scope</th>
              <th>Name</th>
              <th>Slug</th>
              <th>Description</th>
              <th>Version</th>
              <th>Updated</th>
              <th class="text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <%= if @filtered_prompts == [] do %>
              <tr>
                <td colspan="7" class="text-center py-8">
                  <div class="flex flex-col items-center gap-2">
                    <svg
                      class="h-12 w-12 text-gray-400"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="1.5"
                        d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                      />
                    </svg>
                    <p class="text-sm text-gray-500">No prompts found matching your criteria.</p>
                  </div>
                </td>
              </tr>
            <% else %>
              <%= for prompt <- @filtered_prompts do %>
                <tr
                  phx-click={JS.navigate(~p"/prompts/#{prompt.uuid}")}
                  class="hover cursor-pointer group"
                >
                  <td>
                    <%= if is_nil(prompt.project_id) do %>
                      <span class="badge badge-primary badge-sm">Global</span>
                    <% else %>
                      <span class="badge badge-secondary badge-sm">Project</span>
                    <% end %>
                  </td>
                  <td>
                    <div class="font-semibold">{prompt.name}</div>
                  </td>
                  <td>
                    <code class="text-xs bg-base-200 px-2 py-1 rounded">{prompt.slug}</code>
                  </td>
                  <td>
                    <div class="line-clamp-2 max-w-md text-sm" title={prompt.description}>
                      {prompt.description || "—"}
                    </div>
                  </td>
                  <td>
                    <span class="badge badge-ghost badge-sm">v{prompt.version}</span>
                  </td>
                  <td>
                    <span class="text-sm" title={format_datetime_full(prompt.updated_at)}>
                      {relative_time(prompt.updated_at)}
                    </span>
                  </td>
                  <td class="text-right">
                    <div class="flex justify-end gap-2">
                      <.link
                        navigate={~p"/prompts/#{prompt.uuid}"}
                        class="btn btn-ghost btn-xs"
                        title="View prompt details"
                      >
                        <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                          />
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
                          />
                        </svg>
                      </.link>
                      <button
                        class="btn btn-ghost btn-xs"
                        title="Edit prompt"
                      >
                        <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
                          />
                        </svg>
                      </button>
                      <button
                        phx-click="delete"
                        phx-value-id={prompt.uuid}
                        class="btn btn-ghost btn-xs text-error"
                        title="Deactivate prompt"
                        data-confirm="Are you sure you want to deactivate this prompt?"
                      >
                        <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                          />
                        </svg>
                      </button>
                    </div>
                  </td>
                </tr>
              <% end %>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp filter_prompts(assigns) do
    prompts = assigns.prompts
    query = String.downcase(assigns.search_query)
    scope_filter = assigns.scope_filter

    prompts
    |> Enum.filter(fn prompt ->
      # Search filter
      search_match =
        if query == "" do
          true
        else
          String.contains?(String.downcase(prompt.name || ""), query) ||
            String.contains?(String.downcase(prompt.slug || ""), query) ||
            String.contains?(String.downcase(prompt.description || ""), query)
        end

      # Scope filter
      scope_match =
        case scope_filter do
          "all" -> true
          "global" -> is_nil(prompt.project_id)
          "project" -> not is_nil(prompt.project_id)
          _ -> true
        end

      search_match && scope_match
    end)
  end
end
