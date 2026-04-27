defmodule EyeInTheSkyWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality used by your application.
  """
  use EyeInTheSkyWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  # The app.html.heex template provides the sidebar layout.
  embed_templates "layouts/*"

  # ── Public top bar helpers (used by app.html.heex shell) ────────────────────

  @doc "Breadcrumb slot: project link + section label (or DM session name)."
  attr :sidebar_tab, :atom, required: true
  attr :sidebar_project, :any, default: nil
  attr :dm_session_name, :string, default: nil

  def top_bar_breadcrumb(assigns) do
    ~H"""
    <div class="flex items-center flex-shrink-0">
      <%= if @sidebar_project do %>
        <.link
          navigate={~p"/projects/#{@sidebar_project.id}"}
          class="flex items-center gap-1.5 text-[12px] font-medium text-base-content/50 hover:text-base-content/75 hover:bg-base-content/5 px-1.5 py-1 rounded-md transition-colors"
        >
          <.icon name="hero-folder" class="w-3 h-3" />
          {@sidebar_project.name}
        </.link>
        <span class="text-base-content/20 text-sm mx-1 select-none">/</span>
      <% end %>
      <span class="text-[12px] font-semibold text-base-content/75 px-1">
        <%= if @sidebar_tab == :dm && @dm_session_name do %>
          {@dm_session_name}
        <% else %>
          {top_bar_section_label(@sidebar_tab)}
        <% end %>
      </span>
    </div>
    """
  end

  @doc "CTA button slot: renders a primary + button (link or phx-click)."
  attr :label, :string, default: nil
  attr :href, :string, default: nil
  attr :event, :string, default: nil

  def top_bar_cta(assigns) do
    ~H"""
    <%= if @label do %>
      <%= if @href do %>
        <.link
          navigate={@href}
          class="ml-auto flex items-center gap-1 h-7 px-2.5 rounded-md text-[11px] font-medium bg-primary text-primary-content hover:bg-primary/90 transition-colors"
        >
          <.icon name="hero-plus" class="w-3 h-3" />
          {@label}
        </.link>
      <% else %>
        <button
          phx-click={@event}
          class="ml-auto flex items-center gap-1 h-7 px-2.5 rounded-md text-[11px] font-medium bg-primary text-primary-content hover:bg-primary/90 transition-colors"
        >
          <.icon name="hero-plus" class="w-3 h-3" />
          {@label}
        </button>
      <% end %>
    <% end %>
    """
  end


  @doc false
  def top_bar_section_label(:dm), do: "Session"
  def top_bar_section_label(:agents), do: "Agents"
  def top_bar_section_label(:sessions), do: "Sessions"
  def top_bar_section_label(:overview), do: "Sessions"
  def top_bar_section_label(:tasks), do: "Tasks"
  def top_bar_section_label(:kanban), do: "Tasks"
  def top_bar_section_label(:prompts), do: "Prompts"
  def top_bar_section_label(:notes), do: "Notes"
  def top_bar_section_label(:skills), do: "Skills"
  def top_bar_section_label(:teams), do: "Teams"
  def top_bar_section_label(:canvas), do: "Canvas"
  def top_bar_section_label(:chat), do: "Chat"
  def top_bar_section_label(:notifications), do: "Notifications"
  def top_bar_section_label(:usage), do: "Usage"
  def top_bar_section_label(:jobs), do: "Jobs"
  def top_bar_section_label(:config), do: "Config"
  def top_bar_section_label(:settings), do: "Settings"
  def top_bar_section_label(:files), do: "Files"
  def top_bar_section_label(:iam), do: "IAM"
  def top_bar_section_label(_), do: ""

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <%!-- Toast notifications (put_flash :info / :error) are disabled.
           Connection-status banners below are kept. --%>
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
