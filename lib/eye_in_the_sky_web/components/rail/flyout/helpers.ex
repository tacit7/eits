defmodule EyeInTheSkyWeb.Components.Rail.Flyout.Helpers do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :route, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :custom, :boolean, default: false

  def section_header_link(assigns) do
    ~H"""
    <.link
      navigate={@route}
      class="flex-1 min-w-0 flex items-center gap-1.5 rounded hover:bg-base-content/5 -mx-1 px-1 py-0.5 transition-colors group"
    >
      <span class="flex-shrink-0 flex items-center justify-center text-base-content/35 group-hover:text-base-content/60 transition-colors">
        <%= if @custom do %>
          <.custom_icon name={@icon} class="size-3.5" />
        <% else %>
          <.icon name={@icon} class="size-3.5" />
        <% end %>
      </span>
      <span class="text-micro font-semibold uppercase tracking-widest text-base-content/40 group-hover:text-base-content/60 truncate transition-colors">
        {@label}
      </span>
    </.link>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true

  def simple_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class="flex items-center gap-2.5 px-3 py-2 text-sm text-base-content/60 hover:text-base-content/85 hover:bg-base-content/5 transition-colors"
    >
      <.icon name={@icon} class="size-3.5 flex-shrink-0" />
      <span class="truncate">{@label}</span>
    </.link>
    """
  end

  def section_label(:agents), do: "Agents"
  def section_label(:sessions), do: "Sessions"
  def section_label(:tasks), do: "Tasks"
  def section_label(:prompts), do: "Prompts"
  def section_label(:chat), do: "Chat"
  def section_label(:notes), do: "Notes"
  def section_label(:skills), do: "Skills"
  def section_label(:teams), do: "Teams"
  def section_label(:canvas), do: "Canvas"
  def section_label(:notifications), do: "Notifications"
  def section_label(:usage), do: "Usage"
  def section_label(:jobs), do: "Jobs"
  def section_label(:files), do: "Files"
  def section_label(_), do: "Navigation"

  def section_icon(:chat), do: "hero-chat-bubble-left-ellipsis"
  def section_icon(:canvas), do: "hero-squares-2x2"
  def section_icon(:usage), do: "hero-chart-bar"
  def section_icon(:notifications), do: "hero-bell"
  def section_icon(:skills), do: "hero-bolt"
  def section_icon(:prompts), do: "hero-document-text"
  def section_icon(:jobs), do: "hero-clock"
  def section_icon(:files), do: "hero-folder"
  def section_icon(:notes), do: "hero-pencil-square"
  def section_icon(_), do: "hero-list-bullet"

  def dual_page_section?(section),
    do: section in [:sessions, :tasks, :prompts, :notes, :skills, :jobs]

  def agents_route(%{id: id}), do: "/projects/#{id}/agents"
  def agents_route(_), do: "/agents"

  def skills_route(%{id: id}), do: "/projects/#{id}/skills"
  def skills_route(_), do: "/skills"

  def teams_route(%{id: id}), do: "/projects/#{id}/teams"
  def teams_route(_), do: "/teams"

  def project_route_for(:sessions, %{id: id}), do: "/projects/#{id}/sessions"
  def project_route_for(:tasks, %{id: id}), do: "/projects/#{id}/kanban"
  def project_route_for(:prompts, %{id: id}), do: "/projects/#{id}/prompts"
  def project_route_for(:notes, %{id: id}), do: "/projects/#{id}/notes"
  def project_route_for(:jobs, %{id: id}), do: "/projects/#{id}/jobs"
  def project_route_for(_, _), do: nil
end
