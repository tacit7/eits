defmodule EyeInTheSkyWeb.OverviewLive.Notifications do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Events
  alias EyeInTheSky.Notifications
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [relative_time: 1]
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers

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

    if connected?(socket), do: Events.broadcast_rail_context(socket)

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

  def handle_info(_, socket), do: {:noreply, socket}

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

  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

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

  defp category_chip_class("agent"), do: "bg-primary/10 text-primary"
  defp category_chip_class("job"), do: "bg-warning/15 text-warning"
  defp category_chip_class(_), do: "bg-info/10 text-info"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-6">
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 mb-4">
        <h1 class="text-xl font-semibold">Notifications</h1>
        <div class="flex items-center gap-2 flex-wrap">
          <%!-- Category filter --%>
          <div class="inline-flex items-center gap-1 rounded-box bg-base-200/45 p-0.5">
            <button
              class={filter_button_class(@filter == "all")}
              phx-click="filter"
              phx-value-category="all"
            >
              All
            </button>
            <button
              class={filter_button_class(@filter == "agent")}
              phx-click="filter"
              phx-value-category="agent"
            >
              Agent
            </button>
            <button
              class={filter_button_class(@filter == "job")}
              phx-click="filter"
              phx-value-category="job"
            >
              Job
            </button>
            <button
              class={filter_button_class(@filter == "system")}
              phx-click="filter"
              phx-value-category="system"
            >
              System
            </button>
          </div>

          <button
            class="focus-ring inline-flex min-h-[44px] items-center gap-1 rounded-box px-3 text-mini font-medium text-base-content/55 transition-colors hover:bg-base-content/5 hover:text-base-content/80"
            phx-click="mark_all_read"
          >
            <.icon name="hero-check" class="size-4" />
            <span>Mark all read</span>
          </button>
        </div>
      </div>

      <%= if @notifications != [] do %>
        <div class="space-y-1">
          <%= for n <- @notifications do %>
            <% link = resource_link(n) %>
            <div class={[
              "flex items-start gap-3 px-4 py-3 rounded-box transition-colors",
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
                    "text-message",
                    if(!n.read, do: "font-medium", else: "text-base-content/70")
                  ]}>
                    {n.title}
                  </span>
                  <span class={[
                    "inline-flex items-center rounded-box px-1.5 py-0.5 text-micro font-medium",
                    category_chip_class(n.category)
                  ]}>
                    {n.category}
                  </span>
                </div>
                <%= if n.body do %>
                  <p class="text-mini text-base-content/50 mt-0.5 line-clamp-2">{n.body}</p>
                <% end %>
                <div class="flex items-center gap-3 mt-1">
                  <span class="text-mini text-base-content/35">{relative_time(n.inserted_at)}</span>
                  <%= if link do %>
                    <.link
                      navigate={link}
                      class="text-mini text-primary hover:underline inline-flex items-center min-h-[44px] px-1"
                    >
                      View
                    </.link>
                  <% end %>
                </div>
              </div>

              <%!-- Actions --%>
              <%= if !n.read do %>
                <button
                  class="focus-ring inline-flex min-h-[44px] min-w-[44px] items-center justify-center rounded-box text-base-content/40 transition-colors hover:bg-base-content/5 hover:text-base-content/70"
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

  defp filter_button_class(true) do
    "focus-ring min-h-[44px] rounded-box px-3 text-mini font-medium bg-base-100 text-base-content shadow-sm transition-colors"
  end

  defp filter_button_class(false) do
    "focus-ring min-h-[44px] rounded-box px-3 text-mini font-medium text-base-content/45 transition-colors hover:text-base-content/70"
  end
end
