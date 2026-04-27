defmodule EyeInTheSkyWeb.OverviewLive.Notifications do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Notifications
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [relative_time: 1]

  @impl true
  def mount(_params, _session, socket) do
    notifications =
      if connected?(socket) do
        Notifications.subscribe()
        Notifications.list_notifications()
      else
        []
      end

    socket =
      socket
      |> assign(:page_title, "Notifications")
      |> assign(:sidebar_tab, :notifications)
      |> assign(:sidebar_project, nil)
      |> assign(:notifications, notifications)
      |> assign(:filter, "all")

    {:ok, socket}
  end

  @impl true
  def handle_info({:notification_created, _notification}, socket) do
    {:noreply, assign(socket, :notifications, load_notifications(socket.assigns.filter))}
  end

  @impl true
  def handle_info({:notification_read, _id}, socket) do
    {:noreply, assign(socket, :notifications, load_notifications(socket.assigns.filter))}
  end

  @impl true
  def handle_info({:notifications_updated, _}, socket) do
    {:noreply, assign(socket, :notifications, load_notifications(socket.assigns.filter))}
  end

  @impl true
  def handle_event("mark_read", %{"id" => id}, socket) do
    case parse_int(id) do
      nil ->
        {:noreply, socket}

      int_id ->
        case Notifications.mark_read(int_id) do
          {:ok, _} -> :ok
          {:error, _} -> :ok
        end

        {:noreply, assign(socket, :notifications, load_notifications(socket.assigns.filter))}
    end
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
    Notifications.list_notifications(category: category)
  end

  defp resource_link(%{resource_type: "session", resource_id: id}) when is_binary(id),
    do: ~p"/dm/#{id}"

  defp resource_link(%{resource_type: "job_run", resource_id: _id}),
    do: nil

  defp resource_link(%{resource_type: "task", resource_id: _id}),
    do: nil

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
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 mb-4">
        <h1 class="text-xl font-semibold">Notifications</h1>
        <div class="flex items-center gap-2 flex-wrap">
          <%!-- Category filter --%>
          <div class="join">
            <button
              class={"join-item btn btn-sm min-h-[44px] #{if @filter == "all", do: "btn-active"}"}
              phx-click="filter"
              phx-value-category="all"
            >
              All
            </button>
            <button
              class={"join-item btn btn-sm min-h-[44px] #{if @filter == "agent", do: "btn-active"}"}
              phx-click="filter"
              phx-value-category="agent"
            >
              Agent
            </button>
            <button
              class={"join-item btn btn-sm min-h-[44px] #{if @filter == "job", do: "btn-active"}"}
              phx-click="filter"
              phx-value-category="job"
            >
              Job
            </button>
            <button
              class={"join-item btn btn-sm min-h-[44px] #{if @filter == "system", do: "btn-active"}"}
              phx-click="filter"
              phx-value-category="system"
            >
              System
            </button>
          </div>

          <button class="btn btn-ghost btn-sm min-h-[44px]" phx-click="mark_all_read">
            <.icon name="hero-check" class="size-4" /> Mark all read
          </button>
        </div>
      </div>

      <%= if @notifications != [] do %>
        <div class="space-y-1">
          <%= for n <- @notifications do %>
            <% link = resource_link(n) %>
            <div class={[
              "flex items-start gap-3 px-4 py-3 rounded-lg transition-colors",
              if(!n.read, do: "bg-base-200/60", else: "hover:bg-base-200/30")
            ]}>
              <%!-- Category icon --%>
              <div class="pt-0.5">
                <.icon name={category_icon(n.category)} class="size-5 text-base-content/40" />
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
                    <.link
                      navigate={link}
                      class="text-xs text-primary hover:underline inline-flex items-center min-h-[44px] px-1"
                    >
                      View
                    </.link>
                  <% end %>
                </div>
              </div>

              <%!-- Actions --%>
              <%= if !n.read do %>
                <button
                  class="btn btn-ghost btn-xs min-h-[44px] min-w-[44px] text-base-content/40"
                  phx-click="mark_read"
                  phx-value-id={n.id}
                  title="Mark as read"
                >
                  <.icon name="hero-check" class="size-4" />
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
      <% else %>
        <.empty_state
          title="No notifications"
          subtitle="Notifications from agents, jobs, and system events will appear here."
          class="py-16 text-center"
          title_class="text-lg font-semibold text-base-content mb-2"
        >
          <:icon_slot>
            <div class="mx-auto w-24 h-24 bg-base-200 rounded-full flex items-center justify-center mb-4">
              <.icon name="hero-bell" class="size-12 text-base-content/40" />
            </div>
          </:icon_slot>
        </.empty_state>
      <% end %>
    </div>
    """
  end
end
