defmodule EyeInTheSkyWeb.OverviewLive.Notifications do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Notifications
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [relative_time: 1]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Notifications.subscribe()
    end

    socket =
      socket
      |> assign(:page_title, "Notifications")
      |> assign(:sidebar_tab, :notifications)
      |> assign(:sidebar_project, nil)
      |> assign(:notifications, Notifications.list_notifications())
      |> assign(:filter, "all")

    {:ok, socket}
  end

  @impl true
  def handle_info({:notification_created, _notification}, socket) do
    {:noreply, assign(socket, :notifications, load_notifications(socket.assigns.filter))}
  end

  @impl true
  def handle_info({:notification_read, id}, socket) do
    notifications =
      Enum.map(socket.assigns.notifications, fn n ->
        if n.id == id, do: %{n | read: true}, else: n
      end)

    {:noreply, assign(socket, :notifications, notifications)}
  end

  def handle_info({:notifications_updated, _}, socket) do
    {:noreply, assign(socket, :notifications, load_notifications(socket.assigns.filter))}
  end

  @impl true
  def handle_event("mark_read", %{"id" => id}, socket) do
    Notifications.mark_read(String.to_integer(id))
    {:noreply, assign(socket, :notifications, load_notifications(socket.assigns.filter))}
  end

  @impl true
  def handle_event("mark_all_read", _params, socket) do
    Notifications.mark_all_read()
    {:noreply, assign(socket, :notifications, load_notifications(socket.assigns.filter))}
  end

  @impl true
  def handle_event("filter", %{"category" => category}, socket) do
    {:noreply,
     socket
     |> assign(:filter, category)
     |> assign(:notifications, load_notifications(category))}
  end

  defp load_notifications("all"), do: Notifications.list_notifications()

  defp load_notifications(category) do
    Notifications.list_notifications()
    |> Enum.filter(&(&1.category == category))
  end

  defp resource_link(%{resource_type: "session", resource_id: id}) when is_binary(id),
    do: ~p"/dm/#{id}"

  defp resource_link(%{resource_type: "job_run", resource_id: _id}),
    do: ~p"/jobs"

  defp resource_link(%{resource_type: "task", resource_id: id}) when is_binary(id),
    do: ~p"/tasks"

  defp resource_link(_), do: nil

  defp category_icon("agent"), do: "hero-cpu-chip"
  defp category_icon("job"), do: "hero-calendar-days"
  defp category_icon(_), do: "hero-bell"

  defp category_badge_class("agent"), do: "badge-primary"
  defp category_badge_class("job"), do: "badge-warning"
  defp category_badge_class(_), do: "badge-info"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-6">
      <div class="flex flex-wrap items-center justify-between gap-2 mb-4">
        <h1 class="text-xl font-semibold">Notifications</h1>
        <div class="flex items-center gap-2">
          <%!-- Category filter --%>
          <div class="join">
            <button
              class={"join-item btn btn-sm #{if @filter == "all", do: "btn-active"}"}
              phx-click="filter"
              phx-value-category="all"
            >
              All
            </button>
            <button
              class={"join-item btn btn-sm #{if @filter == "agent", do: "btn-active"}"}
              phx-click="filter"
              phx-value-category="agent"
            >
              Agent
            </button>
            <button
              class={"join-item btn btn-sm #{if @filter == "job", do: "btn-active"}"}
              phx-click="filter"
              phx-value-category="job"
            >
              Job
            </button>
            <button
              class={"join-item btn btn-sm #{if @filter == "system", do: "btn-active"}"}
              phx-click="filter"
              phx-value-category="system"
            >
              System
            </button>
          </div>

          <button class="btn btn-ghost btn-sm" phx-click="mark_all_read">
            <.icon name="hero-check" class="w-4 h-4" /> Mark all read
          </button>
        </div>
      </div>

      <%= if length(@notifications) > 0 do %>
        <div class="space-y-1">
          <%= for n <- @notifications do %>
            <% link = resource_link(n) %>
            <div class={[
              "flex items-start gap-3 px-4 py-3 rounded-lg transition-colors",
              if(!n.read, do: "bg-base-200/60", else: "hover:bg-base-200/30")
            ]}>
              <%!-- Category icon --%>
              <div class="pt-0.5">
                <.icon name={category_icon(n.category)} class="w-5 h-5 text-base-content/40" />
              </div>

              <%!-- Content --%>
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <%= if !n.read do %>
                    <span class="w-2 h-2 rounded-full bg-primary flex-shrink-0"></span>
                  <% end %>
                  <span class={[
                    "text-sm",
                    if(!n.read, do: "font-medium", else: "text-base-content/70")
                  ]}>
                    {n.title}
                  </span>
                  <span class={"badge badge-xs #{category_badge_class(n.category)}"}>
                    {n.category}
                  </span>
                </div>
                <%= if n.body do %>
                  <p class="text-xs text-base-content/50 mt-0.5 line-clamp-2">{n.body}</p>
                <% end %>
                <div class="flex items-center gap-3 mt-1">
                  <span class="text-xs text-base-content/35">{relative_time(n.inserted_at)}</span>
                  <%= if link do %>
                    <.link navigate={link} class="text-xs text-primary hover:underline">
                      View
                    </.link>
                  <% end %>
                </div>
              </div>

              <%!-- Actions --%>
              <%= if !n.read do %>
                <button
                  class="btn btn-ghost btn-xs text-base-content/40"
                  phx-click="mark_read"
                  phx-value-id={n.id}
                  title="Mark as read"
                >
                  <.icon name="hero-check" class="w-4 h-4" />
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="text-center py-16">
          <div class="mx-auto w-24 h-24 bg-base-200 rounded-full flex items-center justify-center mb-4">
            <.icon name="hero-bell" class="w-12 h-12 text-base-content/40" />
          </div>
          <h3 class="text-lg font-semibold text-base-content mb-2">No notifications</h3>
          <p class="text-sm text-base-content/60">
            Notifications from agents, jobs, and system events will appear here.
          </p>
        </div>
      <% end %>
    </div>
    """
  end
end
