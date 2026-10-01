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

  @session_preview_limit 18

  def toolbar(assigns) do
    assigns =
      assigns
      |> assign(:available_session_count, count_sessions(assigns.sessions_by_project))
      |> assign(:session_preview_limit, @session_preview_limit)
      |> assign(
        :visible_session_groups,
        visible_session_groups(assigns.sessions_by_project, assigns.session_search)
      )

    ~H"""
    <%!-- Identity: #channel name only — breadcrumb "Chat" comes from top_bar_breadcrumb --%>
    <span class="flex items-center gap-0.5 font-semibold text-mini text-base-content/75 shrink-0">
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
      <details class="relative " id="sender-filter-relative" phx-update="ignore">
        <summary class={[
          "focus-ring flex h-7 items-center gap-1.5 rounded-box px-2 text-mini font-medium transition-colors cursor-pointer list-none [list-style:none] [&::-webkit-details-marker]:hidden",
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
        <div class="eits-menu absolute z-[10] mt-1 w-52 rounded-box border border-base-content/10 bg-base-100 p-1 shadow-lg">
          <button
            type="button"
            phx-click="set_sender_filter"
            phx-value-session_id=""
            class={[
              "focus-ring w-full rounded-box px-3 py-1.5 text-left text-mini transition-colors",
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
              type="button"
              phx-click="set_sender_filter"
              phx-value-session_id={member.session_id}
              class={[
                "focus-ring w-full rounded-box px-3 py-1.5 text-left text-mini transition-colors",
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
      <details class="relative ">
        <summary class="focus-ring flex h-7 items-center gap-1.5 rounded-box px-2 text-mini font-medium transition-colors text-base-content/55 hover:text-base-content/85 hover:bg-base-content/5 cursor-pointer list-none [list-style:none] [&::-webkit-details-marker]:hidden">
          <.icon name="hero-user-group-mini" class="size-3.5" />
          {length(@channel_members)} members
          <.icon name="hero-chevron-down-mini" class="size-3 text-base-content/40" />
        </summary>
        <div class="eits-menu absolute right-0 z-[10] mt-1 w-80 max-w-[calc(100vw-1rem)] rounded-box border border-base-content/10 bg-base-100 shadow-lg">
          <div class="px-3 pb-3 pt-2.5" id="chat-members-panel">
            <div class="flex items-center justify-between mb-2">
              <span class="text-micro uppercase tracking-normal font-medium text-base-content/55">
                Channel Agents
              </span>
            </div>
            <%= if @channel_members != [] do %>
              <div class="space-y-1.5 mb-3">
                <%= for member <- @channel_members do %>
                  <% member_name = member_label(member) %>
                  <div class="group flex items-center gap-1 rounded-box border border-base-content/8 bg-base-content/[0.04] px-2 py-1 transition-colors hover:border-primary/10 hover:bg-primary/5">
                    <a
                      href={~p"/dm/#{member.session_id}"}
                      class="focus-ring min-w-0 flex-1 rounded-box px-0.5 text-left transition-colors hover:text-primary"
                      title={"Open DM for #{member_name} (session ##{member.session_id})"}
                    >
                      <span class="block truncate text-mini font-medium text-base-content/80">
                        {String.slice(member_name, 0, 26)}{if String.length(member_name) > 26,
                          do: "..."}
                      </span>
                      <span class="block font-mono text-micro text-base-content/50">
                        @{member.session_id}
                      </span>
                    </a>
                    <button
                      type="button"
                      phx-click="remove_agent_from_channel"
                      phx-value-session_id={member.session_id}
                      class="focus-ring inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-box border border-transparent text-base-content/45 opacity-70 transition-colors hover:border-error/15 hover:bg-error/10 hover:text-error hover:opacity-100 focus-visible:opacity-100"
                      title={"Remove #{member_name} from channel"}
                      aria-label={"Remove #{member_name} from channel"}
                    >
                      <.icon name="hero-x-mark" class="size-3" />
                    </button>
                  </div>
                <% end %>
              </div>
            <% else %>
              <p class="text-mini text-base-content/50 mb-3">
                No agents in this channel yet.
              </p>
            <% end %>
            <div class="border-t border-base-content/5 pt-2 mt-1">
              <div class="flex items-center justify-between mb-1.5">
                <span class="text-micro uppercase tracking-normal font-medium text-base-content/55">
                  Add Agent
                </span>
                <span
                  :if={@available_session_count > 0}
                  class="font-mono text-micro text-base-content/45"
                >
                  {@available_session_count} available
                </span>
              </div>
              <form id="chat-member-session-search" phx-change="search_sessions" class="mb-2">
                <label for="chat-member-session-search-input" class="sr-only">
                  Search sessions to add
                </label>
                <input
                  id="chat-member-session-search-input"
                  type="text"
                  name="session_search"
                  value={@session_search}
                  placeholder="Search sessions..."
                  class="input input-xs h-7 w-full border-base-content/10 bg-base-200/60 text-mini text-base-content/75 placeholder:text-base-content/40 focus:border-primary/40"
                  autocomplete="off"
                  aria-label="Search sessions to add"
                  phx-debounce="200"
                />
              </form>
              <%= if @visible_session_groups != [] do %>
                <div class="max-h-48 overflow-y-auto space-y-2 pr-0.5">
                  <%= for group <- @visible_session_groups do %>
                    <div>
                      <span class="text-micro font-medium text-base-content/50 uppercase tracking-normal">
                        {group.project_name}
                      </span>
                      <div class="flex flex-wrap gap-1 mt-0.5">
                        <%= for session <- group.sessions do %>
                          <% session_name = session_label(session) %>
                          <button
                            type="button"
                            phx-click="add_agent_to_channel"
                            phx-value-session_id={session.id}
                            class="focus-ring inline-flex h-7 max-w-full items-center gap-1 rounded-box border border-transparent bg-base-content/[0.04] px-2 text-mini text-base-content/60 transition-colors hover:border-primary/10 hover:bg-primary/5 hover:text-primary"
                            title={"Add #{session_name} (@#{session.id}) to channel"}
                            aria-label={"Add #{session_name} session #{session.id} to channel"}
                          >
                            <.icon name="hero-plus-mini" class="size-3 opacity-70" />
                            <span class="max-w-36 truncate font-medium">
                              {String.slice(session_name, 0, 22)}{if String.length(session_name) > 22,
                                do: "..."}
                            </span>
                            <span class="font-mono text-micro text-base-content/50">
                              @{session.id}
                            </span>
                            <span
                              :if={session.model}
                              class="font-mono text-micro text-base-content/45"
                            >
                              {session.model}
                            </span>
                            <%= if session.ended_at do %>
                              <span class="text-micro font-medium text-base-content/50">ended</span>
                            <% end %>
                          </button>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
                <p
                  :if={@session_search == "" and @available_session_count > @session_preview_limit}
                  class="mt-2 text-mini text-base-content/50"
                >
                  Showing first {@session_preview_limit}. Search to narrow the full list.
                </p>
              <% else %>
                <p class="text-mini text-base-content/50 py-1">
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
        type="button"
        phx-click="toggle_agent_drawer"
        class="focus-ring flex h-7 items-center gap-1 rounded-box px-2 text-mini font-medium text-base-content/55 transition-colors hover:bg-base-content/5 hover:text-base-content"
      >
        <.icon name="hero-plus-mini" class="size-3" /> New Agent
      </button>
    </div>
    """
  end

  defp count_sessions(groups) do
    Enum.reduce(groups, 0, fn group, count ->
      count + length(group.sessions || [])
    end)
  end

  defp visible_session_groups(groups, session_search) do
    limit = if String.trim(session_search || "") == "", do: @session_preview_limit, else: 100

    groups
    |> Enum.reduce({[], limit}, fn group, {visible_groups, remaining} ->
      visible_sessions =
        if remaining > 0 do
          Enum.take(group.sessions || [], remaining)
        else
          []
        end

      next_remaining = max(remaining - length(visible_sessions), 0)

      if visible_sessions == [] do
        {visible_groups, next_remaining}
      else
        {[Map.put(group, :sessions, visible_sessions) | visible_groups], next_remaining}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp member_label(member) do
    label = member.session_name || ""

    if String.trim(label) == "" do
      "Session #{member.session_id}"
    else
      label
    end
  end

  defp session_label(session) do
    label = session.name || session.agent_description || ""

    if String.trim(label) == "" do
      "Session #{session.id}"
    else
      label
    end
  end
end
