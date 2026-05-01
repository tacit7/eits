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

  @doc "Section label slot: section name or DM session name. No project breadcrumb — chrome spec shows label only."
  attr :sidebar_tab, :atom, required: true
  attr :dm_session_name, :string, default: nil

  def top_bar_breadcrumb(assigns) do
    ~H"""
    <%= cond do %>
      <% @sidebar_tab == :dm -> %>
        <input
          id="top-bar-session-name"
          type="text"
          value={@dm_session_name || ""}
          placeholder="Session name"
          phx-blur="update_session_name"
          phx-keydown={JS.push("update_session_name") |> JS.focus(to: "#message-input")}
          phx-key="Enter"
          class="text-xs font-semibold text-base-content/75 bg-transparent border-0 outline-none focus:outline-none focus:ring-0 focus:bg-base-content/5 rounded px-1 min-w-[8rem] max-w-[24rem] w-auto placeholder:text-base-content/25 transition-colors"
        />
      <% @sidebar_tab == :chat -> %>
        <%!-- chat toolbar renders #channel-name itself; no label here --%>
      <% true -> %>
        <span class="text-xs font-semibold text-base-content/75 px-1 flex-shrink-0">
          {top_bar_section_label(@sidebar_tab)}
        </span>
    <% end %>
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
          class="ml-auto flex items-center gap-1 h-7 px-2.5 rounded-md text-mini font-medium bg-primary text-primary-content hover:bg-primary/90 transition-colors"
        >
          <.icon name="hero-plus" class="size-3" />
          {@label}
        </.link>
      <% else %>
        <button
          phx-click={@event}
          class="ml-auto flex items-center gap-1 h-7 px-2.5 rounded-md text-mini font-medium bg-primary text-primary-content hover:bg-primary/90 transition-colors"
        >
          <.icon name="hero-plus" class="size-3" />
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
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
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
