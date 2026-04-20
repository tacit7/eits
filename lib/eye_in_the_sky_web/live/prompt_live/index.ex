defmodule EyeInTheSkyWeb.PromptLive.Index do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Prompts
  import EyeInTheSkyWeb.Helpers.ViewHelpers

  @impl true
  def mount(_params, _session, socket) do
    prompts = if connected?(socket), do: Prompts.list_prompts(), else: []

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
          <h1 class="text-base font-semibold leading-6 text-base-content">
            Subagent Prompts
          </h1>
          <p class="mt-2 text-sm text-base-content/70">
            Reusable prompt templates for spawning specialized subagents
          </p>
        </div>
        <div class="mt-4 sm:mt-0 flex items-center gap-2">
          <.link navigate={~p"/prompts/new"} class="btn btn-primary btn-sm gap-2">
            <.icon name="hero-plus" class="h-4 w-4" /> New Prompt
          </.link>
          <label class="swap swap-rotate btn btn-ghost btn-sm btn-circle">
            <input type="checkbox" class="theme-controller" value="dark" />
            <.icon name="hero-sun" class="swap-on h-5 w-5" />
            <.icon name="hero-moon" class="swap-off h-5 w-5" />
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
              <.icon name="hero-magnifying-glass" class="h-5 w-5 text-base-content/30" />
            </div>
            <input
              type="text"
              name="search"
              id="search"
              phx-keyup="search"
              phx-debounce="300"
              value={@search_query}
              class="input input-bordered w-full pl-10 text-base"
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
                    <.icon name="hero-document-text" class="h-12 w-12 text-base-content/30" />
                    <p class="text-sm text-base-content/60">
                      No prompts found matching your criteria.
                    </p>
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
                        class="btn btn-ghost btn-xs min-h-[44px] min-w-[44px]"
                        title="View prompt details"
                      >
                        <.icon name="hero-eye" class="h-4 w-4" />
                      </.link>
                      <button
                        class="btn btn-ghost btn-xs min-h-[44px] min-w-[44px]"
                        title="Edit prompt"
                      >
                        <.icon name="hero-pencil-square" class="h-4 w-4" />
                      </button>
                      <button
                        phx-click="delete"
                        phx-value-id={prompt.uuid}
                        class="btn btn-ghost btn-xs text-error min-h-[44px] min-w-[44px]"
                        title="Deactivate prompt"
                        data-confirm="Are you sure you want to deactivate this prompt?"
                      >
                        <.icon name="hero-trash" class="h-4 w-4" />
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
    query = String.downcase(assigns.search_query)
    scope_filter = assigns.scope_filter

    assigns.prompts
    |> filter_by_search(query)
    |> filter_by_scope(scope_filter)
  end

  defp filter_by_search(prompts, ""), do: prompts

  defp filter_by_search(prompts, query) do
    Enum.filter(prompts, &prompt_matches_search?(&1, query))
  end

  defp prompt_matches_search?(prompt, query) do
    String.contains?(String.downcase(prompt.name || ""), query) ||
      String.contains?(String.downcase(prompt.slug || ""), query) ||
      String.contains?(String.downcase(prompt.description || ""), query)
  end

  defp filter_by_scope(prompts, scope_filter) do
    Enum.filter(prompts, &prompt_matches_scope?(&1, scope_filter))
  end

  defp prompt_matches_scope?(prompt, scope_filter) do
    case scope_filter do
      "all" -> true
      "global" -> is_nil(prompt.project_id)
      "project" -> not is_nil(prompt.project_id)
      _ -> true
    end
  end
end
