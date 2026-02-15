defmodule EyeInTheSkyWebWeb.Components.SessionCard do
  use Phoenix.Component
  import EyeInTheSkyWebWeb.CoreComponents, only: [icon: 1]
  import EyeInTheSkyWebWeb.Helpers.ViewHelpers, only: [relative_time: 1]

  @doc """
  Renders a session card with status pulse, name, description, and metadata.

  ## Attrs
    * `:session` - Map with session_id, session_name, agent_id, project_name, started_at, ended_at
    * `:show_project` - Whether to show project name (default: true)
  """
  attr :session, :map, required: true
  attr :show_project, :boolean, default: true

  def session_card(assigns) do
    status = session_status(assigns.session.started_at, assigns.session.ended_at)
    assigns = assign(assigns, :status, status)

    ~H"""
    <.link
      navigate={"/dm/#{@session.session_id}"}
      class="group relative block rounded-xl bg-base-100 border border-base-content/6 hover:border-primary/30 transition-all duration-300 overflow-hidden"
    >
      <%!-- Subtle top accent line --%>
      <div class={[
        "absolute top-0 left-0 right-0 h-[2px] transition-all duration-300",
        if(@status == "Active",
          do: "bg-gradient-to-r from-success/60 via-success to-success/60",
          else: "bg-gradient-to-r from-transparent via-base-content/6 to-transparent group-hover:via-primary/20"
        )
      ]} />

      <div class="p-4 pt-5 space-y-3">
        <%!-- Top row: status + time --%>
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <%= if @status == "Active" do %>
              <span class="relative flex h-2 w-2">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-success opacity-60"></span>
                <span class="relative inline-flex rounded-full h-2 w-2 bg-success"></span>
              </span>
              <span class="text-[11px] font-semibold tracking-wide uppercase text-success/80">Live</span>
            <% else %>
              <span class="inline-flex rounded-full h-2 w-2 bg-base-content/15"></span>
              <span class="text-[11px] tracking-wide uppercase text-base-content/30">Ended</span>
            <% end %>
          </div>
          <span class="text-[11px] tabular-nums text-base-content/35">{relative_time(@session.started_at)}</span>
        </div>

        <%!-- Session name --%>
        <div class="min-h-[2.5rem]">
          <p class="text-[13px] font-semibold text-base-content/90 line-clamp-1 group-hover:text-primary transition-colors duration-200">
            {@session.session_name || "Unnamed session"}
          </p>
          <%= if Map.get(@session, :agent_description) do %>
            <p class="text-xs text-base-content/40 mt-1 line-clamp-2 leading-relaxed">
              {@session.agent_description}
            </p>
          <% end %>
        </div>

        <%!-- Footer: project + ID --%>
        <div class="flex items-center justify-between pt-2.5 border-t border-base-content/5">
          <%= if @show_project && @session.project_name do %>
            <span class="inline-flex items-center gap-1.5 text-[11px] text-base-content/35">
              <.icon name="hero-folder-mini" class="w-3 h-3 text-base-content/25" />
              <span class="truncate max-w-[120px]">{@session.project_name}</span>
            </span>
          <% else %>
            <span></span>
          <% end %>
          <div class="flex items-center gap-1">
            <code class="text-[10px] font-mono text-base-content/25 tracking-wider">
              {String.slice(@session.session_uuid || "", 0..7)}
            </code>
            <button
              phx-hook="CopyToClipboard"
              id={"copy-#{@session.session_uuid}"}
              data-session-id={@session.session_uuid}
              class="opacity-0 group-hover:opacity-100 transition-opacity duration-200 btn btn-ghost btn-xs btn-square"
              onclick="event.preventDefault(); event.stopPropagation();"
              aria-label="Copy session ID"
            >
              <.icon name="hero-clipboard-document-mini" class="w-3 h-3 text-base-content/40" />
            </button>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  defp session_status(started_at, ended_at) when is_binary(started_at) do
    if ended_at && ended_at != "", do: "Ended", else: "Active"
  end

  defp session_status(_, _), do: "—"
end
