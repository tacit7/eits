defmodule EyeInTheSkyWebWeb.Components.DmPage do
  @moduledoc false

  use EyeInTheSkyWebWeb, :html

  alias EyeInTheSkyWeb.Tasks.WorkflowState

  @tabs [
    {"messages", "hero-chat-bubble-left-right", "Messages"},
    {"tasks", "hero-clipboard-document-list", "Tasks"},
    {"commits", "hero-code-bracket", "Commits"},
    {"notes", "hero-document-text", "Notes"},
    {"timeline", "hero-clock", "Timeline"}
  ]

  attr :agent, :map, required: true
  attr :session_uuid, :string, required: true
  attr :active_tab, :string, required: true
  attr :messages, :list, default: []
  attr :has_more_messages, :boolean, default: false
  attr :uploads, :map, required: true
  attr :selected_model, :string, default: "opus"
  attr :selected_effort, :string, default: "medium"
  attr :show_effort_menu, :boolean, default: false
  attr :show_model_menu, :boolean, default: false
  attr :processing, :boolean, default: false
  attr :tasks, :list, default: []
  attr :commits, :list, default: []
  attr :diff_cache, :map, default: %{}
  attr :notes, :list, default: []
  attr :show_live_stream, :boolean, default: false
  attr :stream_content, :string, default: ""
  attr :stream_tool, :string, default: nil
  attr :stream_thinking, :string, default: nil
  attr :session, :map, default: nil
  attr :slash_items, :list, default: []
  attr :show_new_task_drawer, :boolean, default: false
  attr :workflow_states, :list, default: []
  attr :current_task, :map, default: nil
  attr :total_tokens, :integer, default: 0
  attr :total_cost, :float, default: 0.0
  attr :queued_prompts, :list, default: []
  attr :thinking_enabled, :boolean, default: false
  attr :max_budget_usd, :any, default: nil
  attr :compacting, :boolean, default: false
  attr :context_used, :integer, default: 0
  attr :context_window, :integer, default: 0
  attr :checkpoints, :list, default: []
  attr :show_create_checkpoint, :boolean, default: false

  def dm_page(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <div
      class="flex flex-col h-[100dvh] md:h-[calc(100dvh-2rem)] px-0 sm:px-4 lg:px-8 py-0 sm:py-4 relative"
      id="dm-page"
      phx-drop-target={@uploads.files.ref}
      phx-hook="DragUpload"
    >
      <%!-- Drag overlay --%>
      <div
        id="drag-overlay"
        class="absolute inset-0 z-50 hidden pointer-events-none rounded-xl"
      >
        <div class="absolute inset-3 rounded-xl border-2 border-dashed border-primary/40 bg-primary/[0.04] flex items-center justify-center">
          <div class="text-center">
            <.icon name="hero-arrow-up-tray" class="w-10 h-10 text-primary/50 mx-auto mb-2" />
            <p class="text-sm font-medium text-primary/60">Drop files to attach</p>
          </div>
        </div>
      </div>
      <%!-- Mobile slim top bar (replaces global app header on DM page) --%>
      <div class="md:hidden sticky top-0 z-30 flex-shrink-0 flex items-center gap-1 px-2 pt-[env(safe-area-inset-top)] h-[calc(3rem+env(safe-area-inset-top))] border-b border-base-content/8 bg-base-100">
        <button
          phx-click={Phoenix.LiveView.JS.dispatch("sidebar:open", to: "#app-sidebar")}
          class="btn btn-ghost btn-square w-10 h-10 text-base-content/60"
          aria-label="Open menu"
        >
          <.icon name="hero-bars-3" class="w-5 h-5" />
        </button>
        <div class="flex-1 flex items-center justify-center gap-1.5 min-w-0 px-1">
          <div class={"w-1.5 h-1.5 rounded-full flex-shrink-0 " <> case @agent.status do
            "working" -> "bg-success animate-pulse"
            "waiting" -> "bg-warning animate-pulse"
            "compacting" -> "bg-orange-500 animate-pulse"
            _ -> "bg-base-content/20"
          end} />
          <%= if @agent.entrypoint == "cli" do %>
            <.icon name="hero-command-line" class="w-3.5 h-3.5 text-base-content/40 flex-shrink-0" />
          <% end %>
          <input
            type="text"
            value={@agent.name || ""}
            placeholder="Session name"
            phx-blur="update_session_name"
            phx-keydown={JS.push("update_session_name") |> JS.focus(to: "#message-input")}
            phx-key="Enter"
            class="text-sm font-semibold text-base-content/85 bg-transparent border-0 outline-none focus:outline-none focus:ring-0 focus:bg-base-content/5 rounded px-1 -mx-1 min-w-0 flex-1 text-center placeholder:text-base-content/20 transition-colors"
          />
        </div>
        <div class="dropdown dropdown-end">
          <button
            tabindex="0"
            class="btn btn-ghost btn-square w-10 h-10 text-base-content/60"
            aria-label="More options"
          >
            <.icon name="hero-ellipsis-horizontal" class="w-5 h-5" />
          </button>
          <ul
            tabindex="0"
            class="dropdown-content menu bg-base-100 rounded-box border border-base-content/10 shadow-lg z-50 p-1 w-52 text-xs"
          >
            <%!-- Tab navigation --%>
            <%= for {tab, icon, label} <- @tabs do %>
              <li>
                <button
                  phx-click="change_tab"
                  phx-value-tab={tab}
                  class={[
                    "flex items-center gap-2 px-3 py-2 w-full text-left rounded",
                    @active_tab == tab && "text-primary bg-primary/10",
                    @active_tab != tab && "hover:bg-base-content/5"
                  ]}
                >
                  <.icon name={icon} class="w-3.5 h-3.5" /> {label}
                </button>
              </li>
            <% end %>
            <li><hr class="border-base-content/10 my-1" /></li>
            <li>
              <button
                phx-click="reload_from_session_file"
                data-confirm="This will delete all messages and re-import from the JSONL file. Continue?"
                class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
              >
                <.icon name="hero-arrow-path" class="w-3.5 h-3.5" /> Reload from file
              </button>
            </li>
            <li>
              <button
                phx-click="export_markdown"
                class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
              >
                <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" /> Export as Markdown
              </button>
            </li>
          </ul>
        </div>
      </div>

      <%!-- Header card (desktop only) --%>
      <div
        class="hidden md:block max-w-6xl mx-auto w-full bg-base-200 rounded-2xl border border-base-content/10 shadow-sm mb-3 flex-shrink-0"
        id="dm-header-card"
      >
        <div class="px-4 sm:px-5 py-3" id="dm-header">
          <div class="flex items-center gap-2 min-w-0">
            <%!-- Left: status + name + badges --%>
            <div class="flex items-start gap-2 min-w-0 flex-1">
              <div class={"w-2 h-2 rounded-full flex-shrink-0 mt-[5px] " <> case @agent.status do
                "working" -> "bg-success animate-pulse"
                "waiting" -> "bg-warning animate-pulse"
                "compacting" -> "bg-orange-500 animate-pulse"
                _ -> "bg-base-content/20"
              end} />
              <div class="flex flex-col min-w-0 flex-1">
                <div class="flex items-center gap-2 min-w-0">
                  <%= if @agent.entrypoint == "cli" do %>
                    <.icon name="hero-command-line" class="w-4 h-4 text-base-content/40 flex-shrink-0" />
                  <% end %>
                  <input
                    type="text"
                    value={@agent.name || ""}
                    placeholder="Session name"
                    phx-blur="update_session_name"
                    phx-keydown={JS.push("update_session_name") |> JS.focus(to: "#message-input")}
                    phx-key="Enter"
                    class="text-base sm:text-lg font-bold text-base-content bg-transparent border-0 outline-none focus:outline-none focus:ring-0 focus:bg-base-content/5 rounded px-1 -mx-1 min-w-0 flex-1 placeholder:text-base-content/20 transition-colors"
                  />
                  <button
                    type="button"
                    class="hidden sm:flex items-center gap-1 text-[11px] font-mono text-base-content/30 bg-base-content/5 px-2 py-0.5 rounded hover:text-base-content/50 hover:bg-base-content/8 transition-colors cursor-pointer flex-shrink-0"
                    phx-hook="CopyToClipboard"
                    id="copy-session-uuid"
                    data-copy={@session_uuid}
                  >
                    {if @session_uuid, do: String.slice(@session_uuid, 0..7), else: "—"}
                    <.icon name="hero-clipboard-document" class="w-3 h-3" />
                  </button>
                  <button
                    type="button"
                    phx-click="open_iterm"
                    title="Open in iTerm"
                    class="hidden sm:flex items-center gap-1 text-[11px] text-base-content/30 bg-base-content/5 px-2 py-0.5 rounded hover:text-base-content/50 hover:bg-base-content/8 transition-colors cursor-pointer flex-shrink-0"
                  >
                    <.icon name="hero-command-line" class="w-3 h-3" />
                  </button>
                </div>
                <input
                  type="text"
                  value={@agent.description || ""}
                  placeholder="Add a description..."
                  phx-blur="update_session_description"
                  phx-keydown="update_session_description"
                  phx-key="Enter"
                  class="text-xs text-base-content/40 bg-transparent border-0 outline-none focus:outline-none focus:ring-0 focus:bg-base-content/5 rounded px-1 -mx-1 placeholder:text-base-content/20 transition-colors w-full"
                />
              </div>
            </div>
            <%!-- Right: controls --%>
            <div class="flex items-center gap-1 flex-shrink-0">
              <button
                phx-click="toggle_live_stream"
                phx-hook="LiveStreamToggle"
                id="dm-live-stream-toggle"
                class={[
                  "flex items-center gap-1.5 px-2 sm:px-2.5 py-1 rounded-lg text-xs transition-colors",
                  @show_live_stream && "text-primary bg-primary/10 hover:bg-primary/15",
                  !@show_live_stream &&
                    "text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5"
                ]}
              >
                <.icon
                  name={if @show_live_stream, do: "hero-signal-solid", else: "hero-signal"}
                  class="w-3.5 h-3.5"
                />
                <span class="hidden sm:inline">Live</span>
              </button>
              <button
                phx-click="reload_from_session_file"
                data-confirm="This will delete all messages and re-import from the JSONL file. Continue?"
                class="hidden sm:flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 transition-colors"
                id="dm-reload-button"
              >
                <.icon name="hero-arrow-path" class="w-3.5 h-3.5" /> Reload
              </button>
              <div class="hidden sm:block dropdown dropdown-end" id="dm-export-dropdown">
                <button
                  tabindex="0"
                  class="flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 transition-colors"
                >
                  <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" /> Export
                </button>
                <ul
                  tabindex="0"
                  class="dropdown-content menu bg-base-100 rounded-box border border-base-content/10 shadow-lg z-50 p-1 w-44 text-xs"
                >
                  <li>
                    <button
                      phx-click="export_jsonl"
                      class="px-3 py-2 hover:bg-base-content/5 rounded text-left w-full"
                    >
                      Export as JSONL
                    </button>
                  </li>
                  <li>
                    <button
                      phx-click="export_markdown"
                      class="px-3 py-2 hover:bg-base-content/5 rounded text-left w-full"
                    >
                      Export as Markdown
                    </button>
                  </li>
                </ul>
              </div>
              <button
                id="dm-push-setup-btn"
                phx-hook="PushSetup"
                phx-update="ignore"
                data-push-state="disabled"
                title="Enable push notifications"
                class="flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs transition-colors"
              >
                <.icon name="hero-bell" class="w-3.5 h-3.5" />
                <span>Notify</span>
              </button>
              <%!-- Mobile overflow menu --%>
              <div class="sm:hidden dropdown dropdown-end" id="dm-mobile-menu">
                <button
                  tabindex="0"
                  class="flex items-center justify-center w-7 h-7 rounded-lg text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 transition-colors"
                  title="More options"
                >
                  <.icon name="hero-ellipsis-vertical" class="w-4 h-4" />
                </button>
                <ul
                  tabindex="0"
                  class="dropdown-content menu bg-base-100 rounded-box border border-base-content/10 shadow-lg z-50 p-1 w-52 text-xs"
                >
                  <li>
                    <button
                      phx-click="reload_from_session_file"
                      data-confirm="This will delete all messages and re-import from the JSONL file. Continue?"
                      class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
                    >
                      <.icon name="hero-arrow-path" class="w-3.5 h-3.5" />
                      Reload from file
                    </button>
                  </li>
                  <li>
                    <button
                      phx-click="export_jsonl"
                      class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
                    >
                      <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" />
                      Export as JSONL
                    </button>
                  </li>
                  <li>
                    <button
                      phx-click="export_markdown"
                      class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
                    >
                      <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" />
                      Export as Markdown
                    </button>
                  </li>
                  <li><hr class="border-base-content/10 my-1" /></li>
                </ul>
              </div>
            </div>
          </div>
        </div>

        <%!-- Current task strip --%>
        <%= if @current_task do %>
          <div class="px-5 py-2 border-t border-base-content/5" id="dm-current-task">
            <div class="flex items-center gap-2">
              <span class="text-[10px] font-semibold uppercase tracking-wider text-base-content/30 flex-shrink-0">
                Working on
              </span>
              <div class="flex items-center gap-1.5 min-w-0">
                <div class="w-1.5 h-1.5 rounded-full bg-info animate-pulse flex-shrink-0" />
                <span class="text-[12px] font-medium text-base-content/70 truncate">
                  {@current_task.title}
                </span>
              </div>
              <span class="flex-shrink-0 text-[10px] text-base-content/25 font-mono">
                {String.slice(to_string(@current_task.id), 0..7)}
              </span>
            </div>
          </div>
        <% end %>

        <%!-- Compacting indicator --%>
        <%= if @compacting do %>
          <div class="px-5 py-2 border-t border-orange-500/20 bg-orange-500/5" id="dm-compacting-strip">
            <div class="flex items-center gap-2">
              <div class="w-1.5 h-1.5 rounded-full bg-orange-500 animate-pulse flex-shrink-0" />
              <span class="text-[11px] font-medium text-warning/80">Compacting context...</span>
            </div>
          </div>
        <% end %>

        <%!-- Pill tabs --%>
        <div class="px-5 pb-3 overflow-x-auto" id="dm-tabs">
          <div class="flex items-center gap-1 bg-base-content/[0.03] rounded-lg p-0.5 min-w-max">
            <%= for {tab, icon, label} <- @tabs do %>
              <button
                class={[
                  "flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-medium transition-all duration-150",
                  @active_tab == tab && "bg-base-200 text-base-content shadow-sm",
                  @active_tab != tab && "text-base-content/40 hover:text-base-content/60"
                ]}
                phx-click="change_tab"
                phx-value-tab={tab}
                id={"dm-tab-#{tab}"}
              >
                <.icon name={icon} class="w-3.5 h-3.5" />
                {label}
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Tab content --%>
      <div class="flex-1 min-h-0 max-w-6xl mx-auto w-full" id="dm-tab-content">
        <%= case @active_tab do %>
          <% "messages" -> %>
            <.messages_tab
              messages={@messages}
              has_more_messages={@has_more_messages}
              show_live_stream={@show_live_stream}
              stream_content={@stream_content}
              stream_tool={@stream_tool}
              stream_thinking={@stream_thinking}
              session={@session}
              agent={@agent}
            />
          <% "tasks" -> %>
            <.tasks_tab tasks={@tasks} />
          <% "commits" -> %>
            <.commits_tab commits={@commits} diff_cache={@diff_cache} />
          <% "notes" -> %>
            <.notes_tab notes={@notes} />
          <% "timeline" -> %>
            <.timeline_tab
              checkpoints={@checkpoints}
              show_create_checkpoint={@show_create_checkpoint}
            />
          <% _ -> %>
            <.messages_tab
              messages={@messages}
              has_more_messages={@has_more_messages}
              show_live_stream={@show_live_stream}
              stream_content={@stream_content}
              stream_tool={@stream_tool}
              stream_thinking={@stream_thinking}
              session={@session}
              agent={@agent}
            />
        <% end %>
      </div>

      <%!-- Composer (pinned to bottom) --%>
      <%= if @active_tab in ["messages", nil] do %>
        <div id="dm-page-composer" class="flex-shrink-0 max-w-4xl mx-auto w-full pt-2 safe-inset-bottom">
          <%!-- Prompt queue panel (shown when queue non-empty) --%>
          <%= if @queued_prompts != [] do %>
            <.prompt_queue prompts={@queued_prompts} />
          <% end %>
          <.message_form
            uploads={@uploads}
            selected_model={@selected_model}
            selected_effort={@selected_effort}
            show_effort_menu={@show_effort_menu}
            show_model_menu={@show_model_menu}
            processing={@processing}
            slash_items={@slash_items}
            thinking_enabled={@thinking_enabled}
            max_budget_usd={@max_budget_usd}
            provider={@agent.provider}
            total_tokens={@total_tokens}
            total_cost={@total_cost}
            context_used={@context_used}
            context_window={@context_window}
          />
        </div>
      <% end %>

    </div>
    """
  end

  attr :messages, :list, default: []
  attr :has_more_messages, :boolean, default: false
  attr :show_live_stream, :boolean, default: false
  attr :stream_content, :string, default: ""
  attr :stream_tool, :string, default: nil
  attr :stream_thinking, :string, default: nil
  attr :session, :map, default: nil
  attr :agent, :map, default: nil

  defp messages_tab(assigns) do
    ~H"""
    <div class="flex h-full flex-col" id="dm-messages-tab">
      <div class="flex-1 min-h-0 flex flex-col">
        <div
          class="px-4 py-2 overflow-y-auto flex-1 min-h-0"
          id="messages-container"
          phx-hook="AutoScroll"
          data-has-more={if @has_more_messages, do: "true", else: "false"}
          style="scrollbar-width: none; -ms-overflow-style: none;"
        >
          <%= if @messages == [] do %>
            <div class="flex flex-col items-center justify-center h-full py-20 text-center select-none">
              <.icon name="hero-chat-bubble-left-right" class="w-16 h-16 text-base-content/10 mb-5" />
              <p class="text-base font-medium text-base-content/40">
                {if @agent, do: @agent.name, else: "No messages yet"}
              </p>
              <p class="mt-1.5 text-xs text-base-content/25 max-w-xs">
                <%= if @agent && @agent.git_worktree_path do %>
                  <span class="font-mono">{Path.basename(@agent.git_worktree_path)}</span>
                  &nbsp;&mdash;
                  Send a message to start the conversation
                <% end %>
              </p>
            </div>
          <% else %>
            <div class="py-2 flex items-center justify-center gap-3">
              <%= if @has_more_messages do %>
                <button
                  phx-click="load_more_messages"
                  class="text-xs text-base-content/35 hover:text-primary transition-colors"
                  id="load-more-messages"
                >
                  Load older messages
                </button>
              <% end %>
            </div>

            <div class="space-y-4">
              <%= for message <- @messages do %>
                <.message_item message={message} />
              <% end %>
            </div>

            <%!-- Live streaming bubble --%>
            <%= if @show_live_stream && (@stream_content != "" || @stream_tool || @stream_thinking) do %>
              <div class="py-3 px-2" id="live-stream-bubble">
                <div class="flex items-start gap-2.5">
                  <.stream_provider_avatar session={@session} />
                  <div class="min-w-0 flex-1">
                    <span class="text-[13px] font-semibold text-primary/80">
                      {stream_provider_label(@session)}
                    </span>
                    <%= if @stream_thinking do %>
                      <div class="text-xs text-base-content/30 italic font-mono mt-1 line-clamp-3">
                        {String.slice(@stream_thinking, -200, 200)}
                      </div>
                    <% end %>
                    <%= if @stream_tool do %>
                      <div class="text-xs text-base-content/40 font-mono mt-1">
                        Using {@stream_tool}...
                      </div>
                    <% end %>
                    <%= if @stream_content != "" do %>
                      <div class="mt-1 text-sm text-base-content/60 whitespace-pre-wrap">
                        {@stream_content}
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
            <%!-- Scroll anchor: keeps list pinned to bottom on resize (keyboard open/close) --%>
            <div id="messages-scroll-anchor" style="overflow-anchor: auto; height: 1px;"></div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :message, :map, required: true

  defp message_item(assigns) do
    is_user = assigns.message.sender_role == "user"
    is_dm = dm_message?(assigns.message)
    assigns = assign(assigns, :is_user, is_user) |> assign(:is_dm, is_dm)

    ~H"""
    <div
      class={[
        "py-3 px-2 -mx-2 rounded-lg opacity-0",
        @is_dm && "border-l-2 border-primary/30 pl-3 bg-primary/[0.03]"
      ]}
      id={"dm-message-#{@message.id}"}
      phx-mounted={
        JS.transition(
          {"transition-all ease-out duration-200", "opacity-0 translate-y-1",
           "opacity-100 translate-y-0"}
        )
      }
    >
      <div class="flex items-start gap-2.5">
        <%!-- Sender icon --%>
        <%= if @is_user do %>
          <div class="w-4 h-4 rounded-full mt-1 flex-shrink-0 bg-success/20 flex items-center justify-center">
            <div class="w-1.5 h-1.5 rounded-full bg-success" />
          </div>
        <% else %>
          <img
            src={provider_icon(@message.provider)}
            class={"w-4 h-4 mt-1 flex-shrink-0 #{provider_icon_class(@message.provider)}"}
            alt={@message.provider || "Agent"}
          />
        <% end %>

        <div class="min-w-0 flex-1">
          <div class="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
            <span class={[
              "text-[13px] font-semibold",
              !@is_user && "text-primary/80",
              @is_user && "text-base-content/70"
            ]}>
              {message_sender_name(@message)}
            </span>
            <%!-- DM badge --%>
            <span
              :if={@is_dm}
              class="inline-flex items-center gap-1 text-[10px] font-mono px-1.5 py-0.5 rounded bg-base-content/[0.05] text-base-content/40 uppercase tracking-wide"
            >
              <.icon name="hero-envelope-mini" class="w-2.5 h-2.5" /> dm
            </span>
            <span
              :if={!@is_user && message_model(@message)}
              class="text-[11px] font-mono px-1.5 py-0.5 rounded bg-base-content/[0.05] text-base-content/35"
            >
              {message_model(@message)}
            </span>
            <span
              :if={!@is_user && message_cost(@message)}
              class="text-[11px] font-mono text-base-content/30"
            >
              ${:erlang.float_to_binary(message_cost(@message) * 1.0, decimals: 4)}
            </span>
            <time
              id={"msg-time-#{@message.id}"}
              class="text-[11px] text-base-content/25"
              data-utc={to_utc_string(@message.inserted_at)}
              phx-hook="LocalTime"
            >
            </time>
          </div>

          <.message_body message={@message} />

          <.message_metrics :if={show_message_metrics?(@message)} message={@message} />
          <.message_attachments attachments={@message.attachments || []} />
        </div>
      </div>
    </div>
    """
  end

  attr :message, :map, required: true

  defp message_metrics(assigns) do
    ~H"""
    <div class="mt-2 flex flex-wrap gap-1.5">
      <%= if @message.metadata["total_cost_usd"] do %>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40"
          title="Total cost"
        >
          <.icon name="hero-currency-dollar-mini" class="w-3 h-3" />
          {:erlang.float_to_binary(@message.metadata["total_cost_usd"] * 1.0, decimals: 4)}
        </span>
      <% end %>

      <%= if @message.metadata["usage"] && @message.metadata["usage"]["input_tokens"] do %>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40"
          title="Input tokens"
        >
          {@message.metadata["usage"]["input_tokens"]} in
        </span>
      <% end %>

      <%= if @message.metadata["usage"] && @message.metadata["usage"]["output_tokens"] do %>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40"
          title="Output tokens"
        >
          {@message.metadata["usage"]["output_tokens"]} out
        </span>
      <% end %>

      <%= if @message.metadata["duration_ms"] do %>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40"
          title="Duration"
        >
          <.icon name="hero-clock-mini" class="w-3 h-3" />
          {:erlang.float_to_binary(@message.metadata["duration_ms"] * 1.0 / 1000, decimals: 1)}s
        </span>
      <% end %>

      <%= if @message.metadata["num_turns"] do %>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40"
          title="Number of turns"
        >
          {@message.metadata["num_turns"]} turns
        </span>
      <% end %>
    </div>
    """
  end

  attr :attachments, :list, default: []

  defp message_attachments(assigns) do
    ~H"""
    <%= if @attachments != [] do %>
      <div class="mt-2 space-y-1">
        <%= for attachment <- @attachments do %>
          <div class="flex items-center gap-2 rounded-md bg-base-content/[0.04] px-2.5 py-1.5 text-[11px] font-mono">
            <.icon name="hero-paper-clip" class="h-3 w-3 text-base-content/30" />
            <span class="text-base-content/60">{attachment.original_filename}</span>
            <span class="ml-auto text-base-content/25">{attachment.storage_path}</span>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :message, :map, required: true

  defp message_body(assigns) do
    body = if dm_message?(assigns.message), do: strip_dm_prefix(assigns.message.body), else: assigns.message.body
    segments = parse_body_segments(body)
    thinking = get_in(assigns.message.metadata || %{}, ["thinking"])
    stream_type = get_in(assigns.message.metadata || %{}, ["stream_type"])

    assigns =
      assigns
      |> assign(:segments, segments)
      |> assign(:thinking, thinking)
      |> assign(:stream_type, stream_type)

    ~H"""
    <div class="mt-1 space-y-1.5">
      <details
        :if={@thinking && @thinking != ""}
        class="group rounded border-l-2 border-purple-500/50 bg-zinc-950/50 overflow-hidden"
      >
        <summary class="flex items-center gap-2 px-2.5 py-1.5 cursor-pointer select-none list-none hover:bg-base-content/[0.04] transition-colors">
          <.icon name="hero-sparkles" class="w-3.5 h-3.5 flex-shrink-0 text-purple-400/60" />
          <span class="text-[11px] font-mono font-semibold text-purple-400/60 uppercase tracking-wide">
            Thinking
          </span>
          <.icon
            name="hero-chevron-right"
            class="w-3 h-3 text-base-content/20 ml-auto flex-shrink-0 transition-transform group-open:rotate-90"
          />
        </summary>
        <div class="px-2.5 pb-2 pt-1 border-t border-purple-500/10">
          <pre class="font-mono text-xs text-base-content/40 whitespace-pre-wrap break-words leading-relaxed">{@thinking}</pre>
        </div>
      </details>
      <%= if @stream_type == "tool_result" do %>
        <.tool_result_body body={@message.body} />
      <% else %>
        <%= for {segment, idx} <- Enum.with_index(@segments) do %>
          <%= case segment do %>
            <% {:tool_call, name, rest} -> %>
              <.tool_widget name={name} rest={rest} />
            <% {:text, text} when text != "" -> %>
              <div
                id={"msg-body-#{@message.id}-#{idx}"}
                class="dm-markdown text-sm leading-relaxed text-base-content/85"
                phx-hook="MarkdownMessage"
                data-raw-body={text}
              >
              </div>
            <% _ -> %>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :body, :string, default: ""

  defp tool_result_body(assigns) do
    body = assigns.body || ""
    preview = body |> String.slice(0..100) |> then(&if String.length(body) > 100, do: &1 <> "…", else: &1)
    assigns = assign(assigns, :preview, preview)

    ~H"""
    <details class="group rounded-md border border-base-content/8 bg-base-content/[0.025] overflow-hidden">
      <summary class="flex items-center gap-2 px-2.5 py-1.5 cursor-pointer select-none list-none hover:bg-base-content/[0.04] transition-colors">
        <.icon name="hero-code-bracket" class="w-3.5 h-3.5 flex-shrink-0 text-base-content/30" />
        <span class="text-[11px] font-mono font-semibold text-base-content/40 uppercase tracking-wide flex-shrink-0">
          Output
        </span>
        <span
          :if={@preview != ""}
          class="text-[11px] font-mono text-base-content/25 truncate flex-1 min-w-0"
        >
          {@preview}
        </span>
        <.icon
          name="hero-chevron-right"
          class="w-3 h-3 text-base-content/20 ml-auto flex-shrink-0 transition-transform group-open:rotate-90"
        />
      </summary>
      <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5">
        <pre class="font-mono text-[10px] text-base-content/55 whitespace-pre-wrap break-all leading-relaxed max-h-64 overflow-y-auto">{@body}</pre>
      </div>
    </details>
    """
  end

  attr :name, :string, required: true
  attr :rest, :string, required: true

  defp tool_widget(assigns) do
    {icon, label, detail} = tool_widget_meta(assigns.name, assigns.rest)

    input =
      case Jason.decode(assigns.rest) do
        {:ok, map} when is_map(map) -> map
        _ -> nil
      end

    wrap_detail = label == "i-speak"

    assigns =
      assigns
      |> assign(:icon, icon)
      |> assign(:label, label)
      |> assign(:detail, detail)
      |> assign(:input, input)
      |> assign(:wrap_detail, wrap_detail)

    ~H"""
    <details class="group rounded-md border border-base-content/8 bg-base-content/[0.025] overflow-hidden">
      <summary class="flex items-center gap-2 px-2.5 py-1.5 cursor-pointer select-none list-none hover:bg-base-content/[0.04] transition-colors">
        <.icon name={@icon} class="w-3.5 h-3.5 flex-shrink-0 text-base-content/35" />
        <span class="text-[11px] font-mono font-semibold text-base-content/45 uppercase tracking-wide flex-shrink-0">
          {@label}
        </span>
        <span
          :if={@detail != "" && !@wrap_detail}
          class="text-[11px] font-mono text-base-content/35 truncate flex-1 min-w-0"
        >
          {@detail}
        </span>
        <.icon
          name="hero-chevron-right"
          class="w-3 h-3 text-base-content/20 ml-auto flex-shrink-0 transition-transform group-open:rotate-90"
        />
      </summary>
      <.tool_widget_body name={@name} rest={@rest} detail={@detail} input={@input} />
    </details>
    """
  end

  attr :name, :string, required: true
  attr :rest, :string, required: true
  attr :detail, :string, required: true
  attr :input, :any, default: nil

  defp tool_widget_body(assigns) do
    body_type =
      cond do
        assigns.name == "Bash" and assigns.rest != "" ->
          :bash

        assigns.name == "Edit" and is_map(assigns.input) and
            Map.has_key?(assigns.input, "old_string") ->
          :edit

        assigns.name == "Write" and is_map(assigns.input) and
            Map.has_key?(assigns.input, "content") ->
          :write

        String.ends_with?(assigns.name, "i-speak") and assigns.detail != "" ->
          :speak

        is_map(assigns.input) and map_size(assigns.input) > 0 and
            assigns.name not in ["Read", "Glob", "Grep", "WebSearch", "Task"] ->
          :json

        assigns.rest != "" and assigns.rest != assigns.detail ->
          :text

        true ->
          :none
      end

    assigns = assign(assigns, :body_type, body_type)

    ~H"""
    <%= case @body_type do %>
      <% :bash -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5">
          <pre class="bg-base-200 rounded px-2 py-1.5 font-mono text-[10px] text-base-content/70 whitespace-pre-wrap break-all leading-relaxed">{(@input && @input["command"]) || @detail}</pre>
        </div>
      <% :edit -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5 space-y-1.5">
          <div class="font-mono text-[10px] text-base-content/40 pb-0.5">{@input["file_path"]}</div>
          <pre class="bg-red-950/30 text-red-400/70 rounded px-2 py-1 font-mono text-[10px] whitespace-pre-wrap break-all leading-relaxed max-h-32 overflow-y-auto">{String.slice(@input["old_string"] || "", 0..500)}</pre>
          <pre class="bg-green-950/30 text-green-400/70 rounded px-2 py-1 font-mono text-[10px] whitespace-pre-wrap break-all leading-relaxed max-h-32 overflow-y-auto">{String.slice(@input["new_string"] || "", 0..500)}</pre>
        </div>
      <% :write -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5 space-y-1">
          <div class="font-mono text-[10px] text-base-content/40 pb-0.5">{@input["file_path"]}</div>
          <pre class="bg-base-200 rounded px-2 py-1.5 font-mono text-[10px] text-base-content/55 whitespace-pre-wrap break-all leading-relaxed max-h-48 overflow-y-auto">{String.slice(@input["content"] || "", 0..500)}{if String.length(@input["content"] || "") > 500, do: "\n…", else: ""}</pre>
        </div>
      <% :speak -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5">
          <pre class="bg-base-200 rounded px-2 py-1.5 text-[11px] text-base-content/70 whitespace-pre-wrap break-all leading-relaxed">{@detail}</pre>
        </div>
      <% :json -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5">
          <pre class="font-mono text-[10px] text-base-content/40 whitespace-pre-wrap break-all leading-relaxed max-h-40 overflow-y-auto">{Jason.encode!(@input, pretty: true)}</pre>
        </div>
      <% :text -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5">
          <pre class="font-mono text-[10px] text-base-content/45 whitespace-pre-wrap break-all leading-relaxed">{@rest}</pre>
        </div>
      <% :none -> %>
    <% end %>
    """
  end

  attr :uploads, :map, required: true
  attr :selected_model, :string, default: "opus"
  attr :selected_effort, :string, default: "medium"
  attr :show_effort_menu, :boolean, default: false
  attr :show_model_menu, :boolean, default: false
  attr :processing, :boolean, default: false
  attr :slash_items, :list, default: []
  attr :thinking_enabled, :boolean, default: false
  attr :max_budget_usd, :any, default: nil
  attr :provider, :string, default: "claude"
  attr :total_tokens, :integer, default: 0
  attr :total_cost, :float, default: 0.0
  attr :context_used, :integer, default: 0
  attr :context_window, :integer, default: 0

  defp message_form(assigns) do
    ~H"""
    <form
      phx-submit="send_message"
      phx-change="validate_upload"
      class="rounded-2xl border border-base-content/10 bg-base-200 shadow-sm outline-none"
      id="message-form"
      data-slash-items={Jason.encode!(@slash_items)}
      phx-hook="DmComposer"
    >
      <%!-- Upload previews --%>
      <%= if @uploads.files.entries != [] do %>
        <div class="px-4 pt-3 flex flex-wrap gap-2" id="upload-preview-list">
          <%= for entry <- @uploads.files.entries do %>
            <div class="flex items-center gap-2 rounded-lg bg-base-content/[0.04] px-3 py-1.5 text-xs">
              <.icon name="hero-paper-clip" class="w-3.5 h-3.5 text-base-content/40" />
              <span class="text-base-content/70">{entry.client_name}</span>
              <span class="text-base-content/30">{format_size(entry.client_size)}</span>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                class="text-base-content/30 hover:text-error transition-colors"
                id={"cancel-upload-#{entry.ref}"}
              >
                <.icon name="hero-x-mark-mini" class="w-3.5 h-3.5" />
              </button>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Textarea --%>
      <div class="px-4 pt-3 pb-1">
        <textarea
          name="body"
          rows="1"
          placeholder={if @processing, do: "Queue a message...", else: "Reply..."}
          class="w-full bg-transparent border-0 outline-none focus:ring-0 text-sm resize-none min-h-[28px] max-h-40 overflow-y-hidden placeholder:text-base-content/30 p-0"
          autocomplete="off"
          phx-hook="CommandHistory"
          id="message-input"
        ></textarea>
      </div>

      <%!-- Bottom toolbar --%>
      <div class="flex items-center justify-between px-3 pb-3 pt-1" id="dm-composer-toolbar">
        <%!-- Left: upload button + effort pills (opus only) --%>
        <div class="flex items-center gap-2">
          <label
            for={@uploads.files.ref}
            phx-drop-target={@uploads.files.ref}
            class="flex items-center justify-center w-10 h-10 sm:w-8 sm:h-8 rounded-lg cursor-pointer text-base-content/30 hover:text-base-content/60 hover:bg-base-content/5 transition-colors"
          >
            <.icon name="hero-plus" class="w-5 h-5" />
          </label>
          <.live_file_input upload={@uploads.files} class="hidden" />
          <%!-- Budget cap input --%>
          <div class="flex items-center gap-0.5 text-xs text-base-content/40">
            <span class="font-mono">$</span>
            <input
              type="number"
              min="0"
              step="0.01"
              placeholder=""
              value={@max_budget_usd}
              phx-blur="set_max_budget"
              class="w-16 bg-transparent border-0 outline-none focus:ring-0 text-xs placeholder:text-base-content/20 font-mono p-0 [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
            />
          </div>
          <%= if @selected_model == "opus" do %>
            <div
              class="dropdown dropdown-top"
              phx-click="toggle_effort_menu"
              id="effort-selector-dropdown"
            >
              <button
                type="button"
                tabindex="0"
                class="flex items-center gap-1 px-2 py-1 rounded-lg text-xs text-base-content/50 hover:text-base-content/70 transition-colors"
                id="effort-selector-button"
              >
                <.icon name="hero-adjustments-horizontal" class="w-3.5 h-3.5" />
                <span class="font-medium">{effort_display_name(@selected_effort)}</span>
                <.icon name="hero-chevron-down-mini" class="w-3.5 h-3.5" />
              </button>
              <%= if @show_effort_menu do %>
                <ul
                  tabindex="0"
                  class="dropdown-content menu z-[1] w-52 rounded-xl border border-base-content/8 bg-base-100 p-1.5 shadow-lg"
                  id="effort-selector-menu"
                >
                  <li class="menu-title text-[10px] px-3 pt-1 pb-0.5 text-base-content/40">Effort Level</li>
                  <%= for {label, value, desc, icon_color} <- [
                    {"Low", "low", "Faster and cheaper", "text-success"},
                    {"Medium", "medium", "Balanced (default)", "text-info"},
                    {"High", "high", "Deeper reasoning", "text-warning"}
                  ] do %>
                    <li>
                      <a
                        phx-click="select_effort"
                        phx-value-effort={value}
                        class={[
                          "flex items-center gap-3 rounded-lg px-3 py-2.5 hover:bg-base-content/[0.04]",
                          @selected_effort == value && "bg-base-content/[0.06]"
                        ]}
                      >
                        <.icon name="hero-adjustments-horizontal" class={"w-4 h-4 #{icon_color}"} />
                        <div>
                          <div class="text-sm font-semibold text-base-content/80">{label}</div>
                          <div class="text-[11px] text-base-content/40">{desc}</div>
                        </div>
                        <%= if @selected_effort == value do %>
                          <.icon name="hero-check-mini" class="w-4 h-4 text-primary ml-auto" />
                        <% end %>
                      </a>
                    </li>
                  <% end %>
                </ul>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Center: context used --%>
        <div class="inline-flex items-center gap-2">
          <%= if @context_window > 0 and @context_used > 0 do %>
            <% pct = Float.round(@context_used / @context_window * 100, 1) %>
            <% color_class = cond do
              pct < 60 -> "text-base-content/30"
              pct < 80 -> "text-warning/70"
              true -> "text-error/70"
            end %>
            <span
              class={"inline-flex items-center gap-1 text-[11px] font-mono tabular-nums " <> color_class}
              title={"#{format_number(@context_used)} / #{format_number(@context_window)} tokens used"}
            >
              {pct}% ctx
            </span>
          <% end %>
        </div>

        <%!-- Right: model selector + send/stop --%>
        <div class="flex items-center gap-2">
          <%!-- Model selector --%>
          <div
            class="dropdown dropdown-top dropdown-end"
            phx-click="toggle_model_menu"
            id="model-selector-dropdown"
          >
            <button
              type="button"
              tabindex="0"
              class="flex items-center gap-1 px-2 py-1 rounded-lg text-xs text-base-content/50 hover:text-base-content/70 transition-colors"
              id="model-selector-button"
            >
              <span class="font-medium">{model_display_name(@selected_model)}</span>
              <.icon name="hero-chevron-down-mini" class="w-3.5 h-3.5" />
            </button>

            <%= if @show_model_menu do %>
              <ul
                tabindex="0"
                class="dropdown-content menu z-[1] w-72 rounded-xl border border-base-content/8 bg-base-100 p-1.5 shadow-lg"
                id="model-selector-menu"
              >
                <%= if @provider == "codex" do %>
                  <li class="menu-title text-[10px] px-3 pt-1 pb-0.5 text-base-content/40">Codex</li>
                  <li>
                    <a
                      phx-click="select_model"
                      phx-value-model="gpt-5.4"
                      phx-value-effort=""
                      class="flex items-center gap-3 rounded-lg px-3 py-2.5 hover:bg-base-content/[0.04]"
                    >
                      <.icon name="hero-bolt" class="w-4 h-4 text-warning" />
                      <div>
                        <div class="text-sm font-semibold text-base-content/80">gpt-5.4</div>
                        <div class="text-[11px] text-base-content/40">
                          Latest frontier agentic coding
                        </div>
                      </div>
                    </a>
                  </li>
                  <li>
                    <a
                      phx-click="select_model"
                      phx-value-model="gpt-5.3-codex"
                      phx-value-effort=""
                      class="flex items-center gap-3 rounded-lg px-3 py-2.5 hover:bg-base-content/[0.04]"
                    >
                      <.icon name="hero-bolt" class="w-4 h-4 text-warning" />
                      <div>
                        <div class="text-sm font-semibold text-base-content/80">gpt-5.3-codex</div>
                        <div class="text-[11px] text-base-content/40">Frontier Codex-optimized</div>
                      </div>
                    </a>
                  </li>
                  <li>
                    <a
                      phx-click="select_model"
                      phx-value-model="gpt-5.2-codex"
                      phx-value-effort=""
                      class="flex items-center gap-3 rounded-lg px-3 py-2.5 hover:bg-base-content/[0.04]"
                    >
                      <.icon name="hero-bolt" class="w-4 h-4 text-info" />
                      <div>
                        <div class="text-sm font-semibold text-base-content/80">gpt-5.2-codex</div>
                        <div class="text-[11px] text-base-content/40">Frontier agentic coding</div>
                      </div>
                    </a>
                  </li>
                  <li>
                    <a
                      phx-click="select_model"
                      phx-value-model="gpt-5.2"
                      phx-value-effort=""
                      class="flex items-center gap-3 rounded-lg px-3 py-2.5 hover:bg-base-content/[0.04]"
                    >
                      <.icon name="hero-bolt" class="w-4 h-4 text-info" />
                      <div>
                        <div class="text-sm font-semibold text-base-content/80">gpt-5.2</div>
                        <div class="text-[11px] text-base-content/40">Long-running agents</div>
                      </div>
                    </a>
                  </li>
                  <li>
                    <a
                      phx-click="select_model"
                      phx-value-model="gpt-5.1-codex-max"
                      phx-value-effort=""
                      class="flex items-center gap-3 rounded-lg px-3 py-2.5 hover:bg-base-content/[0.04]"
                    >
                      <.icon name="hero-bolt" class="w-4 h-4 text-success" />
                      <div>
                        <div class="text-sm font-semibold text-base-content/80">
                          gpt-5.1-codex-max
                        </div>
                        <div class="text-[11px] text-base-content/40">Deep and fast reasoning</div>
                      </div>
                    </a>
                  </li>
                  <li>
                    <a
                      phx-click="select_model"
                      phx-value-model="gpt-5.1-codex-mini"
                      phx-value-effort=""
                      class="flex items-center gap-3 rounded-lg px-3 py-2.5 hover:bg-base-content/[0.04]"
                    >
                      <.icon name="hero-bolt" class="w-4 h-4 text-success" />
                      <div>
                        <div class="text-sm font-semibold text-base-content/80">
                          gpt-5.1-codex-mini
                        </div>
                        <div class="text-[11px] text-base-content/40">Cheaper and faster</div>
                      </div>
                    </a>
                  </li>
                <% else %>
                  <li class="menu-title text-[10px] px-3 pt-1 pb-0.5 text-base-content/40">Claude</li>
                  <li>
                    <a
                      phx-click="select_model"
                      phx-value-model="opus"
                      phx-value-effort=""
                      class="flex items-center gap-3 rounded-lg px-3 py-2.5 hover:bg-base-content/[0.04]"
                    >
                      <.icon name="hero-bolt" class="w-4 h-4 text-warning" />
                      <div>
                        <div class="text-sm font-semibold text-base-content/80">Opus 4.6</div>
                        <div class="text-[11px] text-base-content/40">Most capable</div>
                      </div>
                    </a>
                  </li>
                  <li>
                    <a
                      phx-click="select_model"
                      phx-value-model="sonnet"
                      phx-value-effort=""
                      class="flex items-center gap-3 rounded-lg px-3 py-2.5 hover:bg-base-content/[0.04]"
                    >
                      <.icon name="hero-bolt" class="w-4 h-4 text-info" />
                      <div>
                        <div class="text-sm font-semibold text-base-content/80">Sonnet 4.5</div>
                        <div class="text-[11px] text-base-content/40">Everyday tasks</div>
                      </div>
                    </a>
                  </li>
                  <li>
                    <a
                      phx-click="select_model"
                      phx-value-model="haiku"
                      phx-value-effort=""
                      class="flex items-center gap-3 rounded-lg px-3 py-2.5 hover:bg-base-content/[0.04]"
                    >
                      <.icon name="hero-bolt" class="w-4 h-4 text-success" />
                      <div>
                        <div class="text-sm font-semibold text-base-content/80">Haiku 4.5</div>
                        <div class="text-[11px] text-base-content/40">Fast answers</div>
                      </div>
                    </a>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>

          <%!-- Send / Stop button --%>
          <div class="flex items-center gap-1.5">
            <%= if @processing do %>
              <button
                type="submit"
                class="flex items-center justify-center w-10 h-10 sm:w-8 sm:h-8 rounded-lg bg-base-content/[0.06] text-base-content/40 hover:bg-base-content/10 transition-colors"
                id="dm-queue-button"
                title="Add to queue"
              >
                <.icon name="hero-arrow-up-mini" class="w-5 h-5" />
              </button>
              <button
                type="button"
                phx-click="kill_session"
                class="flex items-center justify-center w-10 h-10 sm:w-8 sm:h-8 rounded-lg bg-error/80 text-error-content hover:bg-error transition-colors"
                id="dm-stop-button"
              >
                <.icon name="hero-stop-solid" class="w-4 h-4" />
              </button>
            <% else %>
              <button
                type="submit"
                class="flex items-center justify-center w-10 h-10 sm:w-8 sm:h-8 rounded-lg bg-primary/70 text-primary-content hover:bg-primary transition-colors"
                id="dm-send-button"
              >
                <.icon name="hero-arrow-up-mini" class="w-5 h-5" />
              </button>
            <% end %>
          </div>
        </div>
      </div>
    </form>
    """
  end

  attr :prompts, :list, required: true

  defp prompt_queue(assigns) do
    ~H"""
    <details class="group mb-2" open>
      <summary class="flex items-center gap-2 px-3 py-1.5 rounded-xl border border-base-content/8 bg-base-content/[0.02] cursor-pointer list-none hover:bg-base-content/[0.04] transition-colors select-none">
        <.icon name="hero-clock" class="w-3.5 h-3.5 text-warning/70" />
        <span class="text-[11px] font-medium text-base-content/40 flex-1 uppercase tracking-wide">
          {length(@prompts)} queued
        </span>
        <.icon name="hero-chevron-down" class="w-3 h-3 text-base-content/20" />
      </summary>
      <div class="mt-1 rounded-xl border border-base-content/8 bg-base-content/[0.02] divide-y divide-base-content/5 overflow-hidden">
        <%= for prompt <- @prompts do %>
          <div class="flex items-center gap-2 px-3 py-2">
            <span class="flex-shrink-0 text-[10px] font-mono font-medium uppercase tracking-wide px-1.5 py-0.5 rounded bg-base-content/[0.06] text-base-content/40">
              {model_display_name(prompt.context[:model] || "opus")}
            </span>
            <span class="text-xs text-base-content/50 truncate flex-1 min-w-0">
              {String.slice(prompt.message || "", 0, 80)}{if String.length(prompt.message || "") > 80,
                do: "…"}
            </span>
            <button
              type="button"
              phx-click="remove_queued_prompt"
              phx-value-id={prompt.id}
              class="flex-shrink-0 text-base-content/20 hover:text-error transition-colors"
              title="Remove from queue"
            >
              <.icon name="hero-x-mark-mini" class="w-4 h-4" />
            </button>
          </div>
        <% end %>
      </div>
    </details>
    """
  end

  attr :tasks, :list, default: []

  defp tasks_tab(assigns) do
    ~H"""
    <div class="flex flex-col gap-2">
      <%= if @tasks == [] do %>
        <.empty_state
          id="dm-tasks-empty"
          icon="hero-clipboard-document-list"
          title="No tasks yet"
          subtitle="Tasks from this session will appear here"
        />
      <% else %>
        <div
          class="divide-y divide-base-content/5 bg-base-200 rounded-xl shadow-sm px-4"
          id="dm-task-list"
        >
          <%= for task <- @tasks do %>
            <% has_expandable = task.description || Map.get(task, :notes, []) != [] %>
            <div class="flex items-start" id={"dm-task-#{task.id}"}>
              <%!-- Edit button — outside collapse so checkbox overlay can't intercept --%>
              <button
                type="button"
                phx-click="open_task_detail"
                phx-value-task_id={task.uuid || to_string(task.id)}
                class="flex-shrink-0 min-w-[44px] min-h-[44px] flex items-center justify-center rounded-md text-base-content/25 hover:text-base-content/70 active:text-primary transition-all z-10 md:min-w-0 md:min-h-0 md:mt-3 md:p-1.5"
                title="Edit task"
              >
                <.icon name="hero-pencil-square" class="w-4 h-4 md:w-3.5 md:h-3.5" />
              </button>

            <%!-- Collapse (status dot + title + expandable content) --%>
            <div class={["collapse flex-1", has_expandable && "collapse-arrow"]}>
              <input type="checkbox" class="min-h-0 p-0" disabled={!has_expandable} />
              <div class="collapse-title py-3.5 px-0 min-h-0 flex items-center gap-3">
                <%!-- Status dot --%>
                <div class="flex-shrink-0 w-5 flex justify-center">
                  <%= if task.state_id == WorkflowState.in_progress_id() do %>
                    <span class="relative flex h-2 w-2">
                      <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-info opacity-50"></span>
                      <span class="relative inline-flex rounded-full h-2 w-2 bg-info"></span>
                    </span>
                  <% else %>
                    <span class={[
                      "inline-flex rounded-full h-2 w-2",
                      task.state_id == WorkflowState.done_id() && "bg-success",
                      task.state_id == WorkflowState.in_review_id() && "bg-warning",
                      task.state_id not in [WorkflowState.in_progress_id(), WorkflowState.done_id(), WorkflowState.in_review_id()] && "bg-base-content/20"
                    ]}></span>
                  <% end %>
                </div>

                <%!-- Content --%>
                <div class="flex-1 min-w-0">
                  <span class={[
                    "text-[13px] font-medium truncate block",
                    task.completed_at && "text-base-content/40 line-through",
                    !task.completed_at && "text-base-content/85"
                  ]}>
                    {String.trim(task.title || "")}
                  </span>
                  <div class="flex items-center gap-1.5 mt-0.5 text-[11px]">
                    <%= if task.state do %>
                      <span class={[
                        "font-medium",
                        task.state_id == WorkflowState.in_progress_id() && "text-info/80",
                        task.state_id == WorkflowState.done_id() && "text-success/80",
                        task.state_id == WorkflowState.in_review_id() && "text-warning/80",
                        task.state_id not in [WorkflowState.in_progress_id(), WorkflowState.done_id(), WorkflowState.in_review_id()] && "text-base-content/45"
                      ]}>
                        {task.state.name}
                      </span>
                    <% end %>
                    <%= if task.tags && length(task.tags) > 0 do %>
                      <span class="text-base-content/15">&middot;</span>
                      <span class="text-base-content/35">
                        {Enum.map_join(Enum.take(task.tags, 2), ", ", & &1.name)}
                      </span>
                    <% end %>
                    <span class="text-base-content/15">&middot;</span>
                    <span class="font-mono text-base-content/30">
                      {String.slice(task.uuid || to_string(task.id), 0..7)}
                    </span>
                    <%= if Map.get(task, :notes_count, 0) > 0 do %>
                      <span class="text-base-content/15">&middot;</span>
                      <span class="flex items-center gap-0.5 text-base-content/35">
                        <.icon name="hero-chat-bubble-bottom-center-text" class="w-3 h-3" />
                        {Map.get(task, :notes_count)}
                      </span>
                    <% end %>
                  </div>
                </div>
              </div>
              <%= if has_expandable do %>
                <div class="collapse-content px-0 pt-0 pb-4 pl-8">
                  <%= if task.description do %>
                    <div class="text-sm text-base-content/65 leading-relaxed whitespace-pre-wrap mb-2">{String.trim(task.description)}</div>
                  <% end %>
                  <%= for note <- Map.get(task, :notes, []) do %>
                    <div class="mt-1.5 rounded-lg bg-base-200/60 px-3 py-2">
                      <%= if note.title do %>
                        <div class="text-[11px] font-semibold text-base-content/60 mb-0.5">{note.title}</div>
                      <% end %>
                      <pre class="whitespace-pre-wrap text-xs text-base-content/55 font-mono leading-relaxed">{note.body}</pre>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
          <% end %>
        </div>
      <% end %>
      <button
        phx-click="toggle_new_task_drawer"
        class="flex items-center gap-2 w-full px-3 py-3 rounded-xl text-sm text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 active:bg-base-content/10 transition-colors border border-dashed border-base-content/15 hover:border-base-content/25"
      >
        <.icon name="hero-plus" class="w-4 h-4" />
        Add task
      </button>
    </div>
    """
  end

  attr :commits, :list, default: []
  attr :diff_cache, :map, default: %{}

  defp commits_tab(assigns) do
    ~H"""
    <%= if @commits == [] do %>
      <.empty_state
        id="dm-commits-empty"
        icon="hero-code-bracket"
        title="No commits yet"
        subtitle="Commits from this session will appear here"
      />
    <% else %>
      <div
        class="space-y-1 bg-base-200 rounded-xl shadow-sm p-4"
        id="dm-commit-list"
      >
        <%= for commit <- @commits do %>
          <% hash = commit.commit_hash || "" %>
          <% diff = Map.get(@diff_cache, hash) %>
          <div
            class="collapse collapse-arrow rounded-lg border border-base-content/5 bg-base-200 hover:border-base-content/10 transition-colors"
            id={"dm-commit-#{commit.id}"}
          >
            <input type="checkbox" phx-click="load_diff" phx-value-hash={hash} />
            <div class="collapse-title py-3 px-4 min-h-0">
              <div class="flex items-center gap-3">
                <.icon name="hero-code-bracket" class="h-4 w-4 flex-shrink-0 text-base-content/30" />
                <div class="flex-1 min-w-0">
                  <h3 class="text-[13px] font-semibold text-base-content/85 truncate">
                    {extract_commit_title(commit.commit_message)}
                  </h3>
                  <div class="flex items-center gap-1.5 mt-0.5 text-[11px] text-base-content/30">
                    <span class="font-mono">{String.slice(hash, 0..7)}</span>
                    <span class="text-base-content/15">/</span>
                    <time
                      id={"commit-time-#{commit.id}"}
                      class="tabular-nums"
                      data-utc={to_utc_string(commit.created_at)}
                      data-fmt="short"
                      phx-hook="LocalTime"
                    >
                    </time>
                  </div>
                </div>
              </div>
            </div>
            <div class="collapse-content pb-2 overflow-x-auto">
              <%= cond do %>
                <% is_nil(diff) -> %>
                  <div class="px-4 py-2 text-xs text-base-content/30 italic">Loading diff...</div>
                <% diff == :error -> %>
                  <div class="px-4 py-2 text-xs text-error/60">
                    Could not load diff — repo path unavailable
                  </div>
                <% true -> %>
                  <div
                    id={"diff-#{commit.id}"}
                    phx-hook="DiffViewer"
                    data-diff={diff}
                    class="diff2html-wrap text-xs"
                  />
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :notes, :list, default: []

  defp notes_tab(assigns) do
    ~H"""
    <%= if @notes == [] do %>
      <.empty_state
        id="dm-notes-empty"
        icon="hero-document-text"
        title="No notes yet"
        subtitle="Notes from this session will appear here"
      />
    <% else %>
      <div
        class="space-y-1 bg-base-200 rounded-xl shadow-sm p-4"
        id="dm-note-list"
      >
        <%= for note <- @notes do %>
          <div
            class="collapse collapse-arrow rounded-lg border border-base-content/5 bg-base-200 hover:border-base-content/10 transition-colors"
            id={"dm-note-#{note.id}"}
          >
            <input type="checkbox" />
            <div class="collapse-title py-3 px-4 min-h-0">
              <div class="flex items-center gap-3">
                <%!-- Star button --%>
                <button
                  type="button"
                  phx-click={JS.push("toggle_star", value: %{note_id: note.id})}
                  onclick="event.stopPropagation(); event.preventDefault();"
                  class="flex-shrink-0 p-0.5 rounded transition-transform hover:scale-110"
                  id={"toggle-note-star-#{note.id}"}
                >
                  <.icon
                    name={if note.starred == 1, do: "hero-star-solid", else: "hero-star"}
                    class={"w-4 h-4 #{if note.starred == 1, do: "text-warning", else: "text-base-content/15 hover:text-base-content/30"}"}
                  />
                </button>
                <%!-- Title + meta --%>
                <div class="flex-1 min-w-0">
                  <h3 class="text-[13px] font-semibold text-base-content/85 truncate">
                    {note.title || extract_title(note.body)}
                  </h3>
                  <div class="flex items-center gap-1.5 mt-0.5 text-[11px] text-base-content/30">
                    <span class="font-mono">
                      {String.slice(note.uuid || to_string(note.id), 0..7)}
                    </span>

                    <button
                      type="button"
                      class="z-10 cursor-pointer transition-colors hover:text-primary"
                      phx-hook="CopyToClipboard"
                      id={"copy-note-#{note.id}"}
                      data-copy={note.uuid || to_string(note.id)}
                      onclick="event.stopPropagation(); event.preventDefault();"
                    >
                      <.icon name="hero-clipboard-document" class="h-3 w-3" />
                    </button>

                    <span class="text-base-content/15">/</span>
                    <time
                      id={"note-time-#{note.id}"}
                      class="tabular-nums"
                      data-utc={to_utc_string(note.created_at)}
                      data-fmt="short"
                      phx-hook="LocalTime"
                    >
                    </time>
                  </div>
                </div>
              </div>
            </div>

            <div class="collapse-content px-4 pb-4">
              <div class="pl-[30px]">
                <div
                  id={"note-body-#{note.id}"}
                  class="dm-markdown text-sm text-base-content/70 leading-relaxed"
                  phx-hook="MarkdownMessage"
                  data-raw-body={note.body}
                >
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>

    """
  end

  defp dm_message?(%{from_session_id: id}) when is_integer(id), do: true
  defp dm_message?(%{metadata: %{"from_session_uuid" => uuid}}) when is_binary(uuid) and uuid != "", do: true
  defp dm_message?(_), do: false

  defp message_sender_name(%{sender_role: "user"}), do: "You"

  defp message_sender_name(%{metadata: %{"sender_name" => name}} = _msg)
       when is_binary(name) and name != "" do
    name
  end

  defp message_sender_name(%{from_session_id: id}) when is_integer(id) do
    "session:#{id}"
  end

  defp message_sender_name(message), do: message.provider || "Agent"

  defp strip_dm_prefix(body) when is_binary(body) do
    case Regex.run(~r/^DM from:[^\(]+\(session:[^\)]+\) (.+)$/s, body) do
      [_, content] -> content
      _ -> body
    end
  end

  defp strip_dm_prefix(body), do: body

  defp provider_icon("openai"), do: "/images/openai.svg"
  defp provider_icon("codex"), do: "/images/openai.svg"
  defp provider_icon(_), do: "/images/claude.svg"

  defp provider_icon_class("openai"), do: "dark:invert"
  defp provider_icon_class("codex"), do: "dark:invert"
  defp provider_icon_class(_), do: ""

  defp message_model(%{metadata: %{"model_usage" => model_usage}}) when is_map(model_usage) do
    case Map.keys(model_usage) do
      [model_id | _] -> format_model_id(model_id)
      _ -> nil
    end
  end

  defp message_model(_), do: nil

  defp message_cost(%{metadata: %{"total_cost_usd" => cost}}) when is_number(cost), do: cost
  defp message_cost(_), do: nil

  defp format_model_id(id) when is_binary(id) do
    cond do
      String.contains?(id, "opus") -> "opus"
      String.contains?(id, "sonnet") -> "sonnet"
      String.contains?(id, "haiku") -> "haiku"
      true -> id |> String.split("-") |> Enum.take(2) |> Enum.join("-")
    end
  end

  defp format_model_id(_), do: nil

  defp show_message_metrics?(message) do
    message.sender_role == "agent" and is_map(message.metadata) and
      not is_nil(message.metadata["total_cost_usd"])
  end

  defp to_utc_string(nil), do: ""
  defp to_utc_string(ts) when is_binary(ts), do: ts
  defp to_utc_string(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp to_utc_string(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt) <> "Z"
  defp to_utc_string(_), do: ""

  defp model_display_name("opus"), do: "Opus 4.6"
  defp model_display_name("sonnet"), do: "Sonnet 4.5"
  defp model_display_name("haiku"), do: "Haiku 4.5"
  defp model_display_name("gpt-5.4"), do: "gpt-5.4"
  defp model_display_name("gpt-5.3-codex"), do: "gpt-5.3-codex"
  defp model_display_name("gpt-5.2-codex"), do: "gpt-5.2-codex"
  defp model_display_name("gpt-5.2"), do: "gpt-5.2"
  defp model_display_name("gpt-5.1-codex-max"), do: "gpt-5.1-codex-max"
  defp model_display_name("gpt-5.1-codex-mini"), do: "gpt-5.1-codex-mini"
  defp model_display_name(other), do: other

  defp effort_display_name("low"), do: "Low"
  defp effort_display_name("medium"), do: "Medium"
  defp effort_display_name("high"), do: "High"
  defp effort_display_name(_), do: "Medium"

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp extract_title(nil), do: "Untitled"

  defp extract_title(body) when is_binary(body) do
    body
    |> String.trim()
    |> String.split("\n")
    |> List.first()
    |> String.replace(~r/^#+\s*/, "")
    |> String.slice(0..50)
    |> then(fn text ->
      if String.length(text) >= 50, do: text <> "...", else: text
    end)
  end

  defp extract_commit_title(nil), do: "No message"

  defp extract_commit_title(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.split("\n")
    |> List.first()
    |> String.slice(0..60)
    |> then(fn text ->
      if String.length(text) >= 60, do: text <> "...", else: text
    end)
  end

  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_number(_), do: "0"

  # Tool widget parsing helpers

  defp parse_body_segments(nil), do: [{:text, ""}]

  defp parse_body_segments(body) when is_binary(body) do
    body
    |> String.trim()
    |> String.split(~r/\n\n/, trim: true)
    |> Enum.map(&parse_body_segment/1)
  end

  defp parse_body_segment(text) do
    trimmed = String.trim(text)

    cond do
      # session_reader format: > `ToolName` args...
      match = Regex.run(~r/^> `([^`]+)` ?(.*)/s, trimmed, capture: :all_but_first) ->
        [name, rest] = match
        {:tool_call, name, String.trim(rest)}

      # session_worker format: Tool: ToolName\n{json}
      match = Regex.run(~r/^Tool: ([^\n]+)\n(.*)/s, trimmed, capture: :all_but_first) ->
        [name, json_rest] = match
        {:tool_call, String.trim(name), String.trim(json_rest)}

      true ->
        {:text, text}
    end
  end

  defp tool_widget_meta("Bash", rest) do
    command =
      with {:ok, %{"command" => cmd}} <- Jason.decode(rest) do
        cmd
      else
        _ ->
          case Regex.run(~r/^`(.+?)`/s, rest, capture: :all_but_first) do
            [cmd] -> cmd
            _ -> rest
          end
      end

    {"hero-command-line", "Bash", command}
  end

  defp tool_widget_meta("Read", rest) do
    path = with {:ok, %{"file_path" => p}} <- Jason.decode(rest), do: p, else: (_ -> rest)
    {"hero-document-text", "Read", path}
  end

  defp tool_widget_meta("Write", rest) do
    path = with {:ok, %{"file_path" => p}} <- Jason.decode(rest), do: p, else: (_ -> rest)
    {"hero-pencil-square", "Write", path}
  end

  defp tool_widget_meta("Edit", rest) do
    path = with {:ok, %{"file_path" => p}} <- Jason.decode(rest), do: p, else: (_ -> rest)
    {"hero-pencil-square", "Edit", path}
  end

  defp tool_widget_meta("Glob", rest) do
    pat = with {:ok, %{"pattern" => p}} <- Jason.decode(rest), do: p, else: (_ -> rest)
    {"hero-folder-open", "Glob", pat}
  end

  defp tool_widget_meta("Task", rest) do
    prompt =
      with {:ok, %{"prompt" => p}} <- Jason.decode(rest) do
        String.slice(p, 0..80) <> if(String.length(p) > 81, do: "…", else: "")
      else
        _ -> rest
      end

    {"hero-cpu-chip", "Task", prompt}
  end

  defp tool_widget_meta("Grep", rest) do
    case Jason.decode(rest) do
      {:ok, %{"pattern" => pat} = input} ->
        path = input["path"] || ""
        detail = [pat, path] |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
        {"hero-magnifying-glass", "Grep", detail}

      _ ->
        case Regex.run(~r/^`([^`]+)`\s*(.*)/s, rest, capture: :all_but_first) do
          [pattern, path] ->
            detail = [pattern, path] |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
            {"hero-magnifying-glass", "Grep", detail}

          _ ->
            {"hero-magnifying-glass", "Grep", rest}
        end
    end
  end

  defp tool_widget_meta("WebSearch", rest) do
    query = with {:ok, %{"query" => q}} <- Jason.decode(rest), do: q, else: (_ -> rest)
    {"hero-globe-alt", "WebSearch", query}
  end

  defp tool_widget_meta(name, rest) when is_binary(name) and binary_part(name, 0, 4) == "mcp_" do
    short = name |> String.split("__") |> List.last()

    {icon, detail} =
      case {short, Jason.decode(rest)} do
        {"i-speak", {:ok, %{"message" => msg}}} ->
          {"hero-speaker-wave", msg}

        {"i-speak", _} ->
          msg =
            rest
            |> String.replace_prefix("message: ", "")
            |> String.split(~r/,\s*(?:voice|rate):\s*/)
            |> List.first()
            |> String.trim()

          {"hero-speaker-wave", msg}

        {_, {:ok, input}} when is_map(input) ->
          summary =
            input
            |> Map.to_list()
            |> Enum.take(2)
            |> Enum.filter(fn {_k, v} -> is_binary(v) or is_number(v) or is_atom(v) end)
            |> Enum.map(fn {k, v} -> "#{k}: #{String.slice(to_string(v), 0..40)}" end)
            |> Enum.join(", ")

          {"hero-puzzle-piece", if(summary == "", do: rest, else: summary)}

        _ ->
          {"hero-puzzle-piece", rest}
      end

    {icon, short, detail}
  end

  defp tool_widget_meta(name, rest) do
    {"hero-wrench-screwdriver", name, rest}
  end

  # ─── Timeline Tab ────────────────────────────────────────────────────────────

  attr :checkpoints, :list, default: []
  attr :show_create_checkpoint, :boolean, default: false

  defp timeline_tab(assigns) do
    ~H"""
    <div class="space-y-3 p-4 max-w-2xl" id="dm-timeline">
      <%!-- Header row with create button --%>
      <div class="flex items-center justify-between mb-1">
        <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/40">
          Checkpoints
        </h3>
        <button
          type="button"
          phx-click="toggle_create_checkpoint"
          class="btn btn-xs btn-primary gap-1"
        >
          <.icon name="hero-plus-mini" class="w-3 h-3" /> New
        </button>
      </div>

      <%!-- Create checkpoint form --%>
      <%= if @show_create_checkpoint do %>
        <form
          phx-submit="create_checkpoint"
          class="bg-base-100 rounded-xl border border-base-content/8 p-4 space-y-3"
          id="create-checkpoint-form"
        >
          <div class="space-y-1">
            <label class="text-xs font-medium text-base-content/50">Name</label>
            <input
              type="text"
              name="name"
              placeholder="Checkpoint name (optional)"
              class="input input-sm w-full bg-base-200/50 border-base-content/10 text-sm"
              autocomplete="off"
            />
          </div>
          <div class="space-y-1">
            <label class="text-xs font-medium text-base-content/50">Description</label>
            <input
              type="text"
              name="description"
              placeholder="Brief description (optional)"
              class="input input-sm w-full bg-base-200/50 border-base-content/10 text-sm"
              autocomplete="off"
            />
          </div>
          <div class="flex gap-2 justify-end">
            <button type="button" phx-click="toggle_create_checkpoint" class="btn btn-xs btn-ghost">
              Cancel
            </button>
            <button type="submit" class="btn btn-xs btn-primary">Save Checkpoint</button>
          </div>
        </form>
      <% end %>

      <%!-- Empty state --%>
      <%= if @checkpoints == [] do %>
        <.empty_state
          id="dm-timeline-empty"
          icon="hero-clock"
          title="No checkpoints yet"
          subtitle="Save a checkpoint to snapshot this session's state"
        />
      <% else %>
        <%!-- Timeline list --%>
        <div class="relative">
          <%!-- Vertical line --%>
          <div class="absolute left-[11px] top-2 bottom-2 w-px bg-base-content/10" />

          <div class="space-y-3">
            <%= for checkpoint <- @checkpoints do %>
              <div
                class="flex gap-3 group"
                id={"checkpoint-#{checkpoint.id}"}
              >
                <%!-- Dot --%>
                <div class="flex-shrink-0 w-[23px] flex items-start justify-center pt-1">
                  <div class="w-3 h-3 rounded-full bg-primary/60 border-2 border-primary/30 group-hover:bg-primary transition-colors" />
                </div>

                <%!-- Content card --%>
                <div class="flex-1 min-w-0 pb-1">
                  <div class="bg-base-100 rounded-lg border border-base-content/6 px-3 py-2.5 hover:border-base-content/12 transition-colors">
                    <%!-- Name + index badge --%>
                    <div class="flex items-center gap-2 min-w-0">
                      <span class="text-[13px] font-semibold text-base-content/80 truncate flex-1">
                        {checkpoint.name || "Checkpoint at msg #{checkpoint.message_index}"}
                      </span>
                      <span class="text-[10px] font-mono bg-base-200 text-base-content/40 px-1.5 py-0.5 rounded flex-shrink-0">
                        msg #{checkpoint.message_index}
                      </span>
                    </div>

                    <%!-- Description --%>
                    <%= if checkpoint.description do %>
                      <p class="text-[12px] text-base-content/50 mt-0.5 truncate">
                        {checkpoint.description}
                      </p>
                    <% end %>

                    <%!-- Meta row --%>
                    <div class="flex items-center gap-3 mt-1.5 text-[11px] text-base-content/30">
                      <span class="font-mono">
                        {format_checkpoint_time(checkpoint.inserted_at)}
                      </span>
                      <%= if checkpoint.git_stash_ref do %>
                        <span class="inline-flex items-center gap-0.5 text-success/60">
                          <.icon name="hero-code-bracket-mini" class="w-3 h-3" /> git stash
                        </span>
                      <% end %>
                    </div>

                    <%!-- Action buttons --%>
                    <div class="flex gap-1.5 mt-2">
                      <button
                        type="button"
                        phx-click="restore_checkpoint"
                        phx-value-id={checkpoint.id}
                        class="btn btn-xs btn-ghost gap-1 text-warning/70 hover:text-warning hover:bg-warning/10"
                        data-confirm={"Restore to checkpoint '#{checkpoint.name || "msg #{checkpoint.message_index}"}'? Messages after this point will be deleted."}
                      >
                        <.icon name="hero-arrow-uturn-left-mini" class="w-3 h-3" /> Restore
                      </button>
                      <button
                        type="button"
                        phx-click="fork_checkpoint"
                        phx-value-id={checkpoint.id}
                        class="btn btn-xs btn-ghost gap-1 text-primary/70 hover:text-primary hover:bg-primary/10"
                      >
                        <.icon name="hero-arrow-top-right-on-square-mini" class="w-3 h-3" /> Fork
                      </button>
                      <button
                        type="button"
                        phx-click="delete_checkpoint"
                        phx-value-id={checkpoint.id}
                        class="btn btn-xs btn-ghost gap-1 text-error/50 hover:text-error hover:bg-error/10 ml-auto"
                        data-confirm="Delete this checkpoint?"
                      >
                        <.icon name="hero-trash-mini" class="w-3 h-3" />
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_checkpoint_time(nil), do: "—"

  defp format_checkpoint_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %-d, %H:%M")
  rescue
    _ -> "—"
  end

  defp format_checkpoint_time(_), do: "—"

  attr :session, :map, default: nil

  defp stream_provider_avatar(assigns) do
    provider = if assigns.session, do: assigns.session.provider, else: "claude"
    assigns = assign(assigns, :provider, provider)

    ~H"""
    <%= if @provider == "codex" do %>
      <img
        src="/images/openai.svg"
        class="w-4 h-4 mt-1 flex-shrink-0 animate-pulse"
        alt="Codex"
      />
    <% else %>
      <img
        src="/images/claude.svg"
        class="w-4 h-4 mt-1 flex-shrink-0 animate-pulse"
        alt="Claude"
      />
    <% end %>
    """
  end

  defp stream_provider_label(nil), do: "Agent"
  defp stream_provider_label(%{provider: "codex"}), do: "Codex"
  defp stream_provider_label(%{provider: "openai"}), do: "Codex"
  defp stream_provider_label(_session), do: "Claude"
end
