defmodule EyeInTheSkyWebWeb.Components.SessionCard do
  use Phoenix.Component

  @doc """
  Renders a session card. Used on both the home page and project sessions page.

  ## Attrs
    * `:session` - Map with session_id, session_name, agent_id, project_name, started_at, ended_at
    * `:show_project` - Whether to show project name (default: true)
  """
  attr :session, :map, required: true
  attr :show_project, :boolean, default: true

  def session_card(assigns) do
    ~H"""
    <.link
      navigate={"/agents/#{@session.agent_id}?s=#{@session.session_id}"}
      class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow border border-base-300 hover:border-primary"
    >
      <div class="card-body p-4">
        <!-- Header with Session ID and Copy -->
        <div class="flex items-start justify-between gap-2 mb-3">
          <div class="flex-1 min-w-0">
            <p class="text-xs text-base-content/60 mb-1">Session ID</p>
            <code class="text-sm font-mono font-semibold text-base-content break-all">
              {String.slice(@session.session_id, 0..11)}...
            </code>
          </div>
          <button
            phx-hook="CopyToClipboard"
            id={"copy-#{@session.session_id}"}
            data-session-id={@session.session_id}
            class="btn btn-ghost btn-xs flex-shrink-0"
            onclick="event.preventDefault(); event.stopPropagation();"
          >
            Copy
          </button>
        </div>

        <!-- Session Name -->
        <%= if @session.session_name do %>
          <div class="mb-3">
            <p class="text-xs text-base-content/60 mb-1">Session Name</p>
            <p class="text-sm font-medium text-base-content line-clamp-2">
              {@session.session_name}
            </p>
          </div>
        <% end %>

        <!-- Agent Description -->
        <%= if Map.get(@session, :agent_description) do %>
          <div class="mb-3">
            <p class="text-xs text-base-content/60 mb-1">Description</p>
            <p class="text-sm text-base-content/80 line-clamp-2">
              {@session.agent_description}
            </p>
          </div>
        <% end %>

        <!-- Info -->
        <div class="space-y-2 mb-4 pt-3 border-t border-base-300">
          <%= if @show_project do %>
            <div class="flex items-center justify-between text-xs text-base-content/70">
              <span>Project:</span>
              <span class="font-medium">{@session.project_name || "\u2014"}</span>
            </div>
          <% end %>
          <div class="flex items-center justify-between text-xs text-base-content/70">
            <span>Started:</span>
            <span>{format_timestamp(@session.started_at)}</span>
          </div>
          <div class="flex items-center justify-between text-xs text-base-content/70">
            <span>Status:</span>
            <% status = session_status(@session.started_at, @session.ended_at) %>
            <span class={"badge badge-xs #{if status == "Active", do: "badge-success", else: "badge-ghost"}"}>
              {status}
            </span>
          </div>
        </div>

      </div>
    </.link>
    """
  end

  defp format_timestamp(nil), do: "\u2014"

  defp format_timestamp(timestamp) when is_binary(timestamp) do
    case String.split(timestamp, " ", parts: 3) do
      [date, time | _] -> "#{date} #{String.slice(time, 0..7)}"
      _ -> timestamp
    end
  end

  defp format_timestamp(_), do: "\u2014"

  defp session_status(started_at, ended_at) when is_binary(started_at) do
    if ended_at && ended_at != "", do: "Ended", else: "Active"
  end

  defp session_status(_, _), do: "\u2014"
end
