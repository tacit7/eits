defmodule EyeInTheSkyWeb.Components.Rail.Flyout do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :open, :boolean, required: true
  # On mobile (<md), the flyout is hidden even when open unless mobile_open is also true.
  # This prevents the 236px panel from compressing content on first load.
  attr :mobile_open, :boolean, default: false
  attr :active_section, :atom, required: true
  attr :sidebar_project, :any, default: nil
  # Accepted for assign compatibility with Sidebar interface; unused in MVP (no channel list).
  attr :active_channel_id, :any, default: nil
  attr :flyout_sessions, :list, default: []
  attr :notification_count, :integer, default: 0
  attr :myself, :any, required: true

  def flyout(assigns) do
    ~H"""
    <div
      data-flyout-panel
      class={[
        "flex flex-col border-r border-base-content/8 bg-base-100 overflow-hidden flex-shrink-0 transition-[width] duration-150",
        # w-0 is always the mobile base; md:w-[236px] overrides on desktop when open.
        # w-[236px] overrides on mobile only when mobile_open is also true.
        if(@open, do: "w-0 md:w-[236px]", else: "w-0"),
        if(@open && @mobile_open, do: "w-[236px]")
      ]}
    >
      <div class={["flex flex-col h-full", if(!@open, do: "invisible")]}>
        <div class="flex items-center justify-between px-3.5 py-3 border-b border-base-content/8 flex-shrink-0">
          <span class="text-[10px] font-semibold uppercase tracking-widest text-base-content/40">
            {section_label(@active_section)}
          </span>
          <button
            phx-click="close_flyout"
            phx-target={@myself}
            class="text-base-content/30 hover:text-base-content/60 transition-colors"
            aria-label="Close panel"
          >
            <.icon name="hero-x-mark-mini" class="w-3.5 h-3.5" />
          </button>
        </div>

        <div class="flex-1 overflow-y-auto py-1">
          <%= case @active_section do %>
            <% :sessions -> %>
              <.sessions_content sessions={@flyout_sessions} sidebar_project={@sidebar_project} />
            <% :tasks -> %>
              <.nav_links project={@sidebar_project} section={:tasks} />
            <% :prompts -> %>
              <.nav_links project={@sidebar_project} section={:prompts} />
            <% :chat -> %>
              <.chat_content />
            <% :notes -> %>
              <.nav_links project={@sidebar_project} section={:notes} />
            <% :skills -> %>
              <.simple_link href="/skills" label="All Skills" icon="hero-bolt" />
            <% :teams -> %>
              <.simple_link href="/teams" label="All Teams" icon="hero-users" />
            <% :canvas -> %>
              <.simple_link href="/canvases" label="All Canvases" icon="hero-squares-2x2" />
            <% :notifications -> %>
              <.simple_link href="/notifications" label="Notifications" icon="hero-bell" />
            <% _ -> %>
              <.nav_links project={@sidebar_project} section={:sessions} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Sessions flyout: real data with status dots
  defp sessions_content(assigns) do
    ~H"""
    <% active = Enum.filter(@sessions, &(&1.status in ["working", "waiting"])) %>
    <% stopped = Enum.filter(@sessions, &(&1.status not in ["working", "waiting"])) %>

    <%= if active != [] do %>
      <div class="px-3 pt-2 pb-1 text-[10px] font-semibold uppercase tracking-widest text-base-content/35">
        Active
      </div>
      <.session_row :for={s <- active} session={s} />
    <% end %>

    <%= if stopped != [] do %>
      <div class="px-3 pt-2 pb-1 text-[10px] font-semibold uppercase tracking-widest text-base-content/35">
        Stopped
      </div>
      <.session_row :for={s <- Enum.take(stopped, 8)} session={s} />
    <% end %>

    <%= if @sessions == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No sessions</div>
    <% end %>

    <div class="px-3 pt-2 pb-1 border-t border-base-content/8 mt-1">
      <.link
        navigate={if @sidebar_project, do: "/projects/#{@sidebar_project.id}/sessions", else: "/"}
        class="text-xs text-base-content/40 hover:text-base-content/70 transition-colors"
      >
        View all &rarr;
      </.link>
    </div>
    """
  end

  attr :session, :map, required: true

  defp session_row(assigns) do
    ~H"""
    <.link
      navigate={"/dm/#{@session.id}"}
      class="flex items-center gap-2 px-3 py-2 text-sm text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors"
    >
      <span class={[
        "w-1.5 h-1.5 rounded-full flex-shrink-0",
        status_dot_class(@session.status)
      ]} />
      <span class="truncate font-medium text-xs">{@session.name || "unnamed"}</span>
      <span class="ml-auto text-[10px] text-base-content/30 flex-shrink-0">
        {format_session_time(@session)}
      </span>
    </.link>
    """
  end

  # Chat flyout: navigation links only (no channel list in MVP)
  defp chat_content(assigns) do
    ~H"""
    <.simple_link href="/chat" label="Channels" icon="hero-chat-bubble-left-ellipsis" />
    <.simple_link href="/dms" label="Direct Messages" icon="hero-chat-bubble-left-right" />
    """
  end

  # Generic nav links per section
  attr :project, :any, default: nil
  attr :section, :atom, required: true

  defp nav_links(%{section: :tasks} = assigns) do
    ~H"""
    <.simple_link href="/tasks" label="All Tasks" icon="hero-clipboard-document-list" />
    <%= if @project do %>
      <.simple_link
        href={"/projects/#{@project.id}/kanban"}
        label={"#{@project.name} Board"}
        icon="hero-squares-2x2"
      />
    <% end %>
    """
  end

  defp nav_links(%{section: :prompts} = assigns) do
    ~H"""
    <.simple_link href="/prompts" label="All Prompts" icon="hero-chat-bubble-left-right" />
    <%= if @project do %>
      <.simple_link
        href={"/projects/#{@project.id}/prompts"}
        label={"#{@project.name} Prompts"}
        icon="hero-folder"
      />
    <% end %>
    """
  end

  defp nav_links(%{section: :notes} = assigns) do
    ~H"""
    <.simple_link href="/notes" label="All Notes" icon="hero-document-text" />
    <%= if @project do %>
      <.simple_link
        href={"/projects/#{@project.id}/notes"}
        label={"#{@project.name} Notes"}
        icon="hero-folder"
      />
    <% end %>
    """
  end

  defp nav_links(%{section: :sessions} = assigns) do
    ~H"""
    <.simple_link href="/" label="All Sessions" icon="hero-cpu-chip" />
    <%= if @project do %>
      <.simple_link
        href={"/projects/#{@project.id}/sessions"}
        label={"#{@project.name} Sessions"}
        icon="hero-folder"
      />
    <% end %>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true

  defp simple_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class="flex items-center gap-2.5 px-3 py-2.5 text-sm text-base-content/60 hover:text-base-content/85 hover:bg-base-content/5 transition-colors"
    >
      <.icon name={@icon} class="w-3.5 h-3.5 flex-shrink-0" />
      <span class="truncate">{@label}</span>
    </.link>
    """
  end

  defp section_label(:sessions), do: "Sessions"
  defp section_label(:tasks), do: "Tasks"
  defp section_label(:prompts), do: "Prompts"
  defp section_label(:chat), do: "Chat"
  defp section_label(:notes), do: "Notes"
  defp section_label(:skills), do: "Skills"
  defp section_label(:teams), do: "Teams"
  defp section_label(:canvas), do: "Canvas"
  defp section_label(:notifications), do: "Notifications"
  defp section_label(_), do: "Navigation"

  defp status_dot_class("working"), do: "bg-green-500"
  defp status_dot_class("waiting"), do: "bg-amber-400"
  defp status_dot_class(_), do: "bg-base-content/25"

  # Session.last_activity_at is :utc_datetime_usec — Ecto returns %DateTime{} structs.
  # Binary fallback handles any edge cases (cached data, API responses, etc.)
  defp format_session_time(%{last_activity_at: %DateTime{} = dt}) do
    diff = max(DateTime.diff(DateTime.utc_now(), dt, :second), 0)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86_400 -> "#{div(diff, 3600)}h"
      true -> "#{div(diff, 86_400)}d"
    end
  end

  defp format_session_time(%{last_activity_at: %NaiveDateTime{} = ndt}) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> then(&format_session_time(%{last_activity_at: &1}))
  end

  defp format_session_time(%{last_activity_at: ts}) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> format_session_time(%{last_activity_at: dt})
      _ -> ""
    end
  end

  defp format_session_time(_), do: ""
end
