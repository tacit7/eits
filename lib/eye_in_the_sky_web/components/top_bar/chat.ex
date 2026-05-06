defmodule EyeInTheSkyWeb.TopBar.Chat do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  attr :active_channel, :map, default: nil
  attr :sender_filter, :any, default: nil
  attr :channel_members, :list, default: []
  attr :sessions_by_project, :list, default: []
  attr :session_search, :string, default: ""

  def toolbar(assigns) do
    ~H"""
    <%!-- Identity: #channel name only — breadcrumb "Chat" comes from top_bar_breadcrumb --%>
    <span class="flex items-center gap-0.5 font-semibold text-[12px] text-base-content/75 shrink-0">
      <span class="text-primary/50 font-semibold mr-0.5">#</span>
      <%= if @active_channel do %>
        {@active_channel.name || "channel"}
      <% else %>
        chat
      <% end %>
    </span>
    <%!-- Spacer: pushes action controls to the right --%>
    <div class="flex-1" />
    <%!-- Action group: filter, members, new agent --%>
    <div class="flex items-center gap-1">
      <details class="dropdown dropdown-end" id="sender-filter-dropdown" phx-update="ignore">
        <summary class={[
          "flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs transition-colors cursor-pointer list-none",
          if(@sender_filter,
            do: "text-primary bg-primary/10 hover:bg-primary/15",
            else: "text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5"
          )
        ]}>
          <.icon name="hero-funnel-mini" class="size-3.5" />
          <%= if @sender_filter do %>
            {Enum.find(@channel_members, fn m ->
              to_string(m.session_id) == to_string(@sender_filter)
            end)
            |> then(fn m -> (m && (m.session_name || "@#{m.session_id}")) || "Filtered" end)}
          <% else %>
            Filter
          <% end %>
        </summary>
        <div class="dropdown-content z-[10] mt-1 w-52 bg-base-100 border border-base-content/10 rounded-xl shadow-lg py-1">
          <button
            phx-click="set_sender_filter"
            phx-value-session_id=""
            class={[
              "w-full text-left px-3 py-1.5 text-xs transition-colors",
              if(is_nil(@sender_filter),
                do: "text-primary font-medium",
                else: "text-base-content/60 hover:text-base-content hover:bg-base-content/5"
              )
            ]}
          >
            All agents
          </button>
          <div class="my-0.5 border-t border-base-content/5"></div>
          <%= for member <- @channel_members do %>
            <button
              phx-click="set_sender_filter"
              phx-value-session_id={member.session_id}
              class={[
                "w-full text-left px-3 py-1.5 text-xs transition-colors",
                if(to_string(@sender_filter) == to_string(member.session_id),
                  do: "text-primary font-medium bg-primary/5",
                  else: "text-base-content/60 hover:text-base-content hover:bg-base-content/5"
                )
              ]}
            >
              {member.session_name || "@#{member.session_id}"}
            </button>
          <% end %>
        </div>
      </details>
      <details class="dropdown dropdown-end">
        <summary class="flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs transition-colors text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 cursor-pointer list-none">
          <.icon name="hero-user-group-mini" class="size-3.5" />
          {length(@channel_members)} members
        </summary>
        <div class="dropdown-content z-[10] mt-1 w-80 bg-base-100 border border-base-content/10 rounded-xl shadow-lg">
          <div class="px-5 pb-3 pt-3" id="chat-members-panel">
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
                      class="inline-flex items-center gap-1 font-mono text-mini font-medium px-2 py-0.5 min-h-[44px] rounded-l bg-base-content/[0.04] text-base-content/50 hover:text-primary hover:bg-primary/5 transition-colors border border-transparent hover:border-primary/10"
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
                            class="inline-flex items-center gap-1 font-mono text-mini px-2 py-0.5 min-h-[44px] rounded bg-base-content/[0.03] text-base-content/40 hover:text-primary hover:bg-primary/5 transition-colors border border-transparent hover:border-primary/10"
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
        </div>
      </details>
      <div class="w-px h-4 bg-base-content/10 mx-0.5"></div>
      <button
        phx-click="toggle_agent_drawer"
        class="btn btn-xs btn-ghost gap-1 min-h-[44px] min-w-[44px]"
      >
        <.icon name="hero-plus-mini" class="size-3" /> New Agent
      </button>
    </div>
    """
  end
end
