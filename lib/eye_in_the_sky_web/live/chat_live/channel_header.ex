defmodule EyeInTheSkyWeb.ChatLive.ChannelHeader do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  attr :active_channel, :map, default: nil
  attr :agent_status_counts, :map, default: %{}
  attr :show_members, :boolean, default: false
  attr :channel_members, :list, default: []
  attr :sessions_by_project, :list, default: []
  attr :session_search, :string, default: ""

  def channel_header(assigns) do
    ~H"""
    <div
      class="max-w-6xl mx-auto w-full bg-base-100 rounded-xl border border-base-content/5 shadow-sm mb-3 flex-shrink-0"
      id="chat-header-card"
    >
      <div class="px-5 py-3">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <div class="w-2 h-2 rounded-full flex-shrink-0 bg-success animate-pulse" />
            <h1 class="text-lg font-bold text-base-content">
              <%= if @active_channel do %>
                <span class="text-base-content/30 mr-0.5">#</span>{@active_channel.name || "Channel"}
              <% else %>
                Chat
              <% end %>
            </h1>
            <%= if @active_channel && @active_channel[:description] do %>
              <span class="text-xs text-base-content/30">{@active_channel.description}</span>
            <% end %>
          </div>
          <div class="flex items-center gap-2">
            <%= if @agent_status_counts[:active] do %>
              <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-success/10 text-[11px] font-mono text-success">
                <span class="w-1.5 h-1.5 rounded-full bg-success"></span>
                {@agent_status_counts.active} active
              </span>
            <% end %>
            <%= if @agent_status_counts[:working] do %>
              <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-warning/10 text-[11px] font-mono text-warning">
                <span class="w-1.5 h-1.5 rounded-full bg-warning animate-pulse"></span>
                {@agent_status_counts.working} running
              </span>
            <% end %>
            <button
              phx-click="toggle_members"
              class={[
                "flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs transition-colors",
                if(@show_members,
                  do: "text-primary bg-primary/10 hover:bg-primary/15",
                  else: "text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5"
                )
              ]}
            >
              <.icon name="hero-user-group-mini" class="w-3.5 h-3.5" />
              {length(@channel_members)} members
            </button>
            <button
              phx-click="toggle_agent_drawer"
              class="btn btn-xs btn-primary gap-1"
            >
              <.icon name="hero-plus-mini" class="w-3 h-3" /> New Agent
            </button>
          </div>
        </div>
      </div>

      <%= if @show_members do %>
        <.member_panel
          channel_members={@channel_members}
          sessions_by_project={@sessions_by_project}
          session_search={@session_search}
        />
      <% end %>
    </div>
    """
  end

  attr :channel_members, :list, default: []
  attr :sessions_by_project, :list, default: []
  attr :session_search, :string, default: ""

  defp member_panel(assigns) do
    ~H"""
    <div class="px-5 pb-3 border-t border-base-content/5 pt-3" id="chat-members-panel">
      <div class="flex items-center justify-between mb-2">
        <span class="text-xs uppercase tracking-wider font-medium text-base-content/30">
          Channel Agents
        </span>
      </div>

      <%= if @channel_members != [] do %>
        <div class="flex flex-wrap gap-1.5 mb-3">
          <%= for member <- @channel_members do %>
            <div class="inline-flex items-center gap-0.5 group">
              <a
                href={~p"/dm/#{member.session_id}"}
                class="inline-flex items-center gap-1 font-mono text-[11px] font-medium px-2 py-0.5 rounded-l bg-base-content/[0.04] text-base-content/50 hover:text-primary hover:bg-primary/5 transition-colors border border-transparent hover:border-primary/10"
                title={"Session ##{member.session_id}"}
              >
                @{member.session_id}
                <%= if member.session_name do %>
                  <span class="text-base-content/35">
                    {String.slice(member.session_name, 0, 15)}{if String.length(
                                                                    member.session_name
                                                                  ) > 15, do: "…"}
                  </span>
                <% end %>
              </a>
              <button
                phx-click="remove_agent_from_channel"
                phx-value-session_id={member.session_id}
                class="inline-flex items-center px-1 py-0.5 rounded-r bg-base-content/[0.04] text-base-content/20 hover:text-error hover:bg-error/10 transition-colors border border-transparent opacity-0 group-hover:opacity-100"
                title="Remove from channel"
              >
                <.icon name="hero-x-mark" class="w-2.5 h-2.5" />
              </button>
            </div>
          <% end %>
        </div>
      <% else %>
        <p class="text-xs text-base-content/30 mb-3">
          No agents in this channel yet.
        </p>
      <% end %>

      <div class="border-t border-base-content/5 pt-2 mt-1">
        <div class="flex items-center justify-between mb-1.5">
          <span class="text-xs uppercase tracking-wider font-medium text-base-content/30">
            Add Agent
          </span>
        </div>
        <form phx-change="search_sessions" class="mb-2">
          <input
            type="text"
            name="session_search"
            value={@session_search}
            placeholder="Search sessions..."
            class="w-full input input-xs bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 text-base"
            autocomplete="off"
            phx-debounce="200"
          />
        </form>
        <%= if @sessions_by_project != [] do %>
          <div class="max-h-48 overflow-y-auto space-y-2">
            <%= for group <- @sessions_by_project do %>
              <div>
                <span class="text-xs font-medium text-base-content/25 uppercase tracking-wider">
                  {group.project_name}
                </span>
                <div class="flex flex-wrap gap-1 mt-0.5">
                  <%= for session <- group.sessions do %>
                    <button
                      phx-click="add_agent_to_channel"
                      phx-value-session_id={session.id}
                      class="inline-flex items-center gap-1 font-mono text-[11px] px-2 py-0.5 rounded bg-base-content/[0.03] text-base-content/40 hover:text-primary hover:bg-primary/5 transition-colors border border-transparent hover:border-primary/10"
                      title={"Add @#{session.id} to channel"}
                    >
                      <.icon name="hero-plus-mini" class="w-2.5 h-2.5 opacity-50" />
                      @{session.id}
                      <span class="text-base-content/25">
                        {String.slice(session.name || session.agent_description || "", 0, 20)}{if String.length(
                                                                                                    session.name ||
                                                                                                      session.agent_description ||
                                                                                                      ""
                                                                                                  ) >
                                                                                                    20,
                                                                                                  do:
                                                                                                    "…"}
                      </span>
                      <span class="text-xs text-base-content/15">{session.model}</span>
                      <%= if session.ended_at do %>
                        <span class="text-xs text-base-content/15">ended</span>
                      <% end %>
                    </button>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <p class="text-xs text-base-content/25 py-1">
            <%= if @session_search != "" do %>
              No sessions match "{@session_search}"
            <% else %>
              No available sessions
            <% end %>
          </p>
        <% end %>
      </div>
    </div>
    """
  end
end
