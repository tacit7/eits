defmodule EyeInTheSkyWeb.Components.FavoriteFabComponent do
  @moduledoc """
  Server-side LiveComponent for the floating action button (FAB) radial menu.

  Renders the main button and agent buttons based on bookmarks pushed from the
  client (localStorage) and live statuses fetched from the server.

  The JS hook `FavoriteFab` handles only positioning, CSS transitions, and
  click events (expand/collapse, chat open).
  """

  use EyeInTheSkyWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:bookmarks, [])
     |> assign(:statuses, %{})}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="FavoriteFab"
      class={["fab fab-flower", if(Enum.empty?(@bookmarks), do: "hidden", else: "")]}
      style="position:fixed;bottom:1rem;right:1rem;width:200px;height:200px;overflow:visible;pointer-events:none"
    >
      <%= if not Enum.empty?(@bookmarks) do %>
        <%!-- Main toggle button --%>
        <div
          tabindex="0"
          role="button"
          style="position:absolute;bottom:0;right:0;z-index:2;pointer-events:auto"
          class="btn btn-primary btn-circle shadow-lg outline-none"
        >
          <.icon name="hero-user" class="w-6 h-6" />
        </div>

        <%!-- Agent buttons (radial positions set by JS hook on mounted/updated) --%>
        <%= for {agent, index} <- Enum.with_index(@bookmarks) do %>
          <% status_style = agent_status_style(agent, @statuses) %>
          <a
            href={"/dm/#{agent["session_id"]}"}
            class="btn btn-circle bg-base-100 shadow-md hover:bg-base-200 border border-base-content/10 relative group fab-agent-btn"
            style="position:absolute;bottom:0;right:0;opacity:0;transform:translate(0,0) scale(0.5);transition:opacity 0.18s,transform 0.18s;pointer-events:none"
            title={agent["name"] || "Agent"}
            data-agent-index={index}
            data-session-id={agent["session_id"]}
            data-agent-name={agent["name"]}
            data-agent-status={agent_live_status(agent, @statuses)}
          >
            <span class="font-bold text-xs text-base-content/70">
              <%= initials(agent["name"]) %>
            </span>

            <%!-- Status dot --%>
            <%= if status_style.ping do %>
              <span class="absolute -bottom-0.5 -right-0.5 flex h-3 w-3">
                <span class={[
                  "animate-ping absolute inline-flex h-full w-full rounded-full opacity-50",
                  status_style.dot
                ]}>
                </span>
                <span class={[
                  "relative inline-flex rounded-full h-3 w-3 ring-2 ring-base-100",
                  status_style.dot
                ]}>
                </span>
              </span>
            <% else %>
              <span class={[
                "absolute -bottom-0.5 -right-0.5 inline-flex rounded-full h-3 w-3 ring-2 ring-base-100",
                status_style.dot
              ]}>
              </span>
            <% end %>

            <%!-- Remove button (shown on hover) --%>
            <span
              class="fab-remove-btn absolute -top-1 -right-1 w-4 h-4 rounded-full bg-error text-error-content flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer z-10 shadow-sm"
              data-remove-index={index}
              style="pointer-events:auto"
            >
              <.icon name="hero-x-mark" class="w-2.5 h-2.5" />
            </span>

            <%!-- Tooltip --%>
            <span class="absolute -top-8 left-1/2 -translate-x-1/2 px-2 py-1 bg-base-300 text-base-content text-xs rounded shadow-lg whitespace-nowrap opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none">
              <%= agent["name"] || "Agent" %>
            </span>
          </a>
        <% end %>
      <% end %>
    </div>
    """
  end

  # --- helpers ---

  defp agent_live_status(agent, statuses) do
    statuses[agent["session_id"]] || agent["status"] || "idle"
  end

  defp agent_status_style(agent, statuses) do
    status = agent_live_status(agent, statuses)

    case status do
      s when s in ["working", "compacting"] -> %{dot: "bg-success", ping: true}
      _ -> %{dot: "bg-base-content/20", ping: false}
    end
  end

  defp initials(nil), do: "?"

  defp initials(name) do
    name
    |> String.split(" ")
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.slice(0, 2)
    |> String.upcase()
  end
end
