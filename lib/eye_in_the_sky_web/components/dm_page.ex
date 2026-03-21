defmodule EyeInTheSkyWeb.Components.DmPage do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Components.DmPage.MessagesTab
  alias EyeInTheSkyWeb.Components.DmPage.TasksTab
  alias EyeInTheSkyWeb.Components.DmPage.CommitsTab
  alias EyeInTheSkyWeb.Components.DmPage.NotesTab
  alias EyeInTheSkyWeb.Components.DmPage.Composer

  @tabs [
    {"messages", "hero-chat-bubble-left-right", "Messages"},
    {"tasks", "hero-clipboard-document-list", "Tasks"},
    {"commits", "hero-code-bracket", "Commits"},
    {"notes", "hero-document-text", "Notes"}
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
  attr :message_search_query, :string, default: ""
  def dm_page(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <div
      class="flex flex-col h-[100dvh] md:h-[calc(100dvh-2rem)] px-0 sm:px-4 lg:px-8 py-0 sm:py-4 relative"
      id="dm-page"
      phx-drop-target={@uploads.files.ref}
      phx-hook="DragUpload"
    >
      <%!-- Reload confirm modal --%>
      <dialog id="dm-reload-confirm-modal" class="modal" phx-hook="ReloadConfirmModal">
        <div class="modal-box">
          <h3 class="font-semibold text-base">Reload from file?</h3>
          <p class="py-3 text-sm text-base-content/70">
            This will delete all messages and re-import from the JSONL file.
          </p>
          <div class="form-control mb-4">
            <label class="label cursor-pointer gap-2 justify-start">
              <input type="checkbox" data-reload-skip class="checkbox checkbox-sm" />
              <span class="label-text text-sm">Don't show this message again</span>
            </label>
          </div>
          <div class="modal-action">
            <button data-reload-cancel class="btn btn-ghost btn-sm">Cancel</button>
            <button data-reload-confirm class="btn btn-error btn-sm">Reload</button>
          </div>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button data-reload-cancel>close</button>
        </form>
      </dialog>

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

      <%!-- Mobile slim top bar --%>
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
                phx-click={JS.dispatch("dm:reload-check", to: "#dm-reload-confirm-modal")}
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
                    <.icon
                      name="hero-command-line"
                      class="w-4 h-4 text-base-content/40 flex-shrink-0"
                    />
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
                phx-click={JS.dispatch("dm:reload-check", to: "#dm-reload-confirm-modal")}
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
                      phx-click={JS.dispatch("dm:reload-check", to: "#dm-reload-confirm-modal")}
                      class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
                    >
                      <.icon name="hero-arrow-path" class="w-3.5 h-3.5" /> Reload from file
                    </button>
                  </li>
                  <li>
                    <button
                      phx-click="export_jsonl"
                      class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
                    >
                      <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" /> Export as JSONL
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
          <div
            class="px-5 py-2 border-t border-orange-500/20 bg-orange-500/5"
            id="dm-compacting-strip"
          >
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
            <MessagesTab.messages_tab
              messages={@messages}
              has_more_messages={@has_more_messages}
              show_live_stream={@show_live_stream}
              stream_content={@stream_content}
              stream_tool={@stream_tool}
              stream_thinking={@stream_thinking}
              session={@session}
              agent={@agent}
              message_search_query={@message_search_query}
            />
          <% "tasks" -> %>
            <TasksTab.tasks_tab tasks={@tasks} />
          <% "commits" -> %>
            <CommitsTab.commits_tab commits={@commits} diff_cache={@diff_cache} />
          <% "notes" -> %>
            <NotesTab.notes_tab notes={@notes} />
          <% _ -> %>
            <MessagesTab.messages_tab
              messages={@messages}
              has_more_messages={@has_more_messages}
              show_live_stream={@show_live_stream}
              stream_content={@stream_content}
              stream_tool={@stream_tool}
              stream_thinking={@stream_thinking}
              session={@session}
              agent={@agent}
              message_search_query={@message_search_query}
            />
        <% end %>
      </div>

      <%!-- Composer (pinned to bottom) --%>
      <%= if @active_tab in ["messages", nil] do %>
        <div
          id="dm-page-composer"
          class="flex-shrink-0 max-w-4xl mx-auto w-full pt-2 safe-inset-bottom"
        >
          <%= if @queued_prompts != [] do %>
            <Composer.prompt_queue prompts={@queued_prompts} />
          <% end %>
          <Composer.message_form
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
end
