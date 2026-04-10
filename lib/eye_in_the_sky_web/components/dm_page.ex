defmodule EyeInTheSkyWeb.Components.DmPage do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Components.DmPage.ActionMenu
  alias EyeInTheSkyWeb.Components.DmPage.CommitsTab
  alias EyeInTheSkyWeb.Components.DmPage.Composer
  alias EyeInTheSkyWeb.Components.DmPage.ContextTab
  alias EyeInTheSkyWeb.Components.DmPage.MessagesTab
  alias EyeInTheSkyWeb.Components.DmPage.NotesTab
  alias EyeInTheSkyWeb.Components.DmPage.TasksTab

  @tabs [
    {"messages", "hero-chat-bubble-left-right", "Messages"},
    {"tasks", "hero-clipboard-document-list", "Tasks"},
    {"commits", "hero-code-bracket", "Commits"},
    {"notes", "hero-document-text", "Notes"},
    {"context", "hero-document-magnifying-glass", "Context"}
  ]

  attr :agent, :map, required: true
  attr :session_uuid, :string, required: true
  attr :active_tab, :string, required: true
  attr :uploads, :map, required: true
  attr :stream, :map, default: %{show: false, content: "", tool: nil, thinking: nil}
  attr :session_state, :map, required: true
  attr :commits, :list, default: []
  attr :diff_cache, :map, default: %{}
  attr :notes, :list, default: []
  attr :slash_items, :list, default: []
  attr :session_context, :map, default: nil
  attr :agent_record, :map, default: nil
  # Grouped maps replacing 10 individual attrs
  attr :message_data, :map,
    default: %{messages: [], has_more_messages: false, message_search_query: "", queued_prompts: []}

  attr :task_data, :map, default: %{tasks: [], current_task: nil}

  attr :overlay_data, :map,
    default: %{active_overlay: nil, active_timer: nil, reloading: false}
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

      <%!-- Schedule timer modal --%>
      <%= if @overlay_data.active_overlay == :schedule_timer do %>
        <div class="modal modal-open" id="schedule-timer-modal">
          <div class="modal-box max-w-sm">
            <h3 class="font-semibold text-base mb-3">Schedule Message</h3>

            <form id="schedule-timer-form" phx-submit="schedule_timer">
              <input type="hidden" name="mode" id="timer-mode-input" value="once" />
              <input type="hidden" name="preset" id="timer-preset-input" value="15m" />

              <div class="mb-4">
                <label class="text-xs font-medium text-base-content/60 mb-1.5 block">Message</label>
                <textarea
                  name="message"
                  rows="3"
                  class="textarea textarea-bordered w-full text-base resize-none"
                  placeholder="Message to send when timer fires..."
                ><%= EyeInTheSky.OrchestratorTimers.default_message() %></textarea>
              </div>

              <div class="mb-3">
                <p class="text-xs font-medium text-base-content/60 mb-2">Once</p>
                <div class="flex flex-wrap gap-1.5">
                  <%= for preset <- ["5m", "10m", "15m", "30m", "1h"] do %>
                    <button
                      type="submit"
                      phx-click={
                        JS.set_attribute({"value", "once"}, to: "#timer-mode-input")
                        |> JS.set_attribute({"value", preset}, to: "#timer-preset-input")
                      }
                      class="btn btn-sm btn-outline"
                    >{preset}</button>
                  <% end %>
                </div>
              </div>

              <div class="mb-4">
                <p class="text-xs font-medium text-base-content/60 mb-2">Repeating</p>
                <div class="flex flex-wrap gap-1.5">
                  <%= for preset <- ["5m", "10m", "15m", "30m", "1h"] do %>
                    <button
                      type="submit"
                      phx-click={
                        JS.set_attribute({"value", "repeating"}, to: "#timer-mode-input")
                        |> JS.set_attribute({"value", preset}, to: "#timer-preset-input")
                      }
                      class="btn btn-sm btn-outline"
                    >{preset}</button>
                  <% end %>
                </div>
              </div>

              <div class="modal-action">
                <button type="button" phx-click="close_schedule_modal" class="btn btn-ghost btn-sm">Cancel</button>
              </div>
            </form>
          </div>
          <div class="modal-backdrop" phx-click="close_schedule_modal"></div>
        </div>
      <% end %>

      <%!-- Reload loading overlay --%>
      <div
        :if={@overlay_data.reloading}
        class="absolute inset-0 z-40 flex items-center justify-center bg-base-100/80 backdrop-blur-sm rounded-xl"
      >
        <div class="flex flex-col items-center gap-3">
          <span class="loading loading-spinner loading-lg text-primary"></span>
          <p class="text-sm text-base-content/60">Reloading messages...</p>
        </div>
      </div>

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
          class="btn btn-ghost btn-square w-10 h-10 text-base-content/60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-1"
          aria-label="Open menu"
        >
          <.icon name="hero-bars-3" class="w-5 h-5" />
        </button>
        <div class="flex-1 flex items-center justify-center gap-1.5 min-w-0 px-1">
          <.status_dot status={@agent.status} class="w-1.5 h-1.5" />
          <%= if @agent.entrypoint == "cli" do %>
            <.icon name="hero-command-line" class="w-3.5 h-3.5 text-base-content/40 flex-shrink-0" />
          <% end %>
          <div class="flex flex-col items-center min-w-0 flex-1">
            <input
              type="text"
              value={@agent.name || ""}
              placeholder="Session name"
              phx-blur="update_session_name"
              phx-keydown={JS.push("update_session_name") |> JS.focus(to: "#message-input")}
              phx-key="Enter"
              class="text-base font-semibold text-base-content/85 bg-transparent border-0 outline-none focus:outline-none focus:ring-0 focus:bg-base-content/5 rounded px-1 -mx-1 min-w-0 w-full text-center placeholder:text-base-content/20 transition-colors"
            />
            <%= if @agent_record && is_map(@agent_record.agent_definition) && not match?(%Ecto.Association.NotLoaded{}, @agent_record.agent_definition) && @agent_record.agent_definition.display_name do %>
              <span class="text-xs text-base-content/35 truncate">{@agent_record.agent_definition.display_name}</span>
            <% end %>
          </div>
        </div>
        <ActionMenu.action_menu
          button_class="btn btn-ghost btn-square w-10 h-10 text-base-content/60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-1"
          show_tabs={true}
          tabs={@tabs}
          active_tab={@active_tab}
          reload_label="Reload from file"
          active_timer={@overlay_data.active_timer}
          schedule_btn_id="dm-schedule-timer-btn"
          cancel_btn_id="dm-cancel-timer-btn"
        />
      </div>

      <%!-- Header card (desktop only) --%>
      <div
        class="hidden md:block max-w-6xl mx-auto w-full bg-base-200 rounded-2xl border border-base-content/10 shadow-sm mb-3 flex-shrink-0"
        id="dm-header-card"
      >
        <div class="px-4 sm:px-5 py-3" id="dm-header">
          <div class="flex items-center gap-2 min-w-0">
            <div class="flex items-start gap-2 min-w-0 flex-1">
              <.status_dot status={@agent.status} class="w-2 h-2 mt-[5px]" />
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
                </div>
                <input
                  type="text"
                  value={@agent.description || ""}
                  placeholder="Add a description..."
                  phx-blur="update_session_description"
                  phx-keydown="update_session_description"
                  phx-key="Enter"
                  class="text-base text-base-content/40 bg-transparent border-0 outline-none focus:outline-none focus:ring-0 focus:bg-base-content/5 rounded px-1 -mx-1 placeholder:text-base-content/20 transition-colors w-full"
                />
              </div>
            </div>
            <div class="flex items-center gap-1 flex-shrink-0">
              <%!-- Active timer badge --%>
              <%= if @overlay_data.active_timer do %>
                <div class="hidden sm:flex items-center gap-1 px-2 py-1 rounded-lg bg-warning/10 text-warning text-xs font-medium">
                  <.icon name="hero-clock" class="w-3.5 h-3.5" />
                  <span>{if @overlay_data.active_timer.mode == :once, do: "Once", else: "Repeating"}</span>
                </div>
              <% end %>

              <%!-- Unified hamburger menu (desktop + mobile) --%>
              <ActionMenu.action_menu
                wrapper_id="dm-actions-menu"
                button_class="btn btn-ghost btn-square w-9 h-9 text-base-content/60"
                show_jsonl_export={true}
                show_push_setup={true}
                show_iterm={true}
                reload_label="Reload"
                active_timer={@overlay_data.active_timer}
                cancel_btn_id="dm-cancel-timer-btn-desktop"
              />
            </div>
          </div>
        </div>

        <%!-- Current task strip --%>
        <%= if @task_data.current_task do %>
          <div class="px-5 py-2 border-t border-base-content/5" id="dm-current-task">
            <div class="flex items-center gap-2">
              <span class="text-xs font-semibold uppercase tracking-wider text-base-content/30 flex-shrink-0">
                Working on
              </span>
              <div class="flex items-center gap-1.5 min-w-0">
                <div class="w-1.5 h-1.5 rounded-full bg-info animate-pulse flex-shrink-0" />
                <span class="text-[12px] font-medium text-base-content/70 truncate">
                  {@task_data.current_task.title}
                </span>
              </div>
              <span class="flex-shrink-0 text-xs text-base-content/25 font-mono">
                {String.slice(to_string(@task_data.current_task.id), 0..7)}
              </span>
            </div>
          </div>
        <% end %>

        <%!-- Compacting indicator --%>
        <%= if @session_state.compacting do %>
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
        <div class="px-5 pb-3 flex items-center gap-3" id="dm-tabs">
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
          <%= if @active_tab in ["messages", nil] do %>
            <div class="ml-auto w-48">
              <form phx-change="search_messages" phx-submit="search_messages" class="relative">
                <.icon
                  name="hero-magnifying-glass"
                  class="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-base-content/30 pointer-events-none"
                />
                <input
                  type="text"
                  name="query"
                  value={@message_data.message_search_query}
                  placeholder="Search messages..."
                  autocomplete="off"
                  phx-debounce="300"
                  class="w-full pl-8 pr-7 py-1.5 text-base rounded-lg bg-base-content/[0.05] border border-base-content/8 focus:outline-none focus:ring-1 focus:ring-primary/30 focus:border-primary/30 placeholder:text-base-content/25 text-base-content/70 transition-colors"
                />
                <%= if @message_data.message_search_query != "" do %>
                  <button
                    type="button"
                    phx-click="search_messages"
                    phx-value-query=""
                    class="absolute right-2 top-1/2 -translate-y-1/2 text-base-content/30 hover:text-base-content/60 transition-colors"
                  >
                    <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
                  </button>
                <% end %>
              </form>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Tab content --%>
      <div class="flex-1 min-h-0 max-w-6xl mx-auto w-full" id="dm-tab-content">
        <%= case @active_tab do %>
          <% "messages" -> %>
            <MessagesTab.messages_tab
              messages={@message_data.messages}
              has_more_messages={@message_data.has_more_messages}
              stream={@stream}
              session={@agent}
              agent={@agent}
              message_search_query={@message_data.message_search_query}
            />
          <% "tasks" -> %>
            <TasksTab.tasks_tab tasks={@task_data.tasks} />
          <% "commits" -> %>
            <CommitsTab.commits_tab commits={@commits} diff_cache={@diff_cache} />
          <% "notes" -> %>
            <NotesTab.notes_tab notes={@notes} />
          <% "context" -> %>
            <ContextTab.context_tab session_context={@session_context} />
          <% _ -> %>
            <MessagesTab.messages_tab
              messages={@message_data.messages}
              has_more_messages={@message_data.has_more_messages}
              stream={@stream}
              session={@agent}
              agent={@agent}
              message_search_query={@message_data.message_search_query}
            />
        <% end %>
      </div>

      <%!-- Composer (pinned to bottom) --%>
      <%= if @active_tab in ["messages", nil] do %>
        <div
          id="dm-page-composer"
          class="flex-shrink-0 max-w-4xl mx-auto w-full pt-2 safe-inset-bottom"
        >
          <%= if @message_data.queued_prompts != [] do %>
            <Composer.prompt_queue prompts={@message_data.queued_prompts} />
          <% end %>
          <Composer.message_form
            uploads={@uploads}
            selected_model={@session_state.model}
            selected_effort={@session_state.effort}
            active_overlay={@overlay_data.active_overlay}
            processing={@session_state.processing}
            slash_items={@slash_items}
            thinking_enabled={@session_state.thinking_enabled}
            max_budget_usd={@session_state.max_budget_usd}
            provider={@agent.provider}
            context_used={@session_state.context_used}
            context_window={@session_state.context_window}
            display_name={if @agent_record && is_map(@agent_record.agent_definition) && not match?(%Ecto.Association.NotLoaded{}, @agent_record.agent_definition), do: @agent_record.agent_definition.display_name}
            session_cli_opts={assigns[:session_cli_opts] || []}
          />
        </div>
      <% end %>
    </div>
    """
  end

  attr :status, :string, required: true
  attr :class, :string, default: "w-2 h-2"

  defp status_dot(assigns) do
    ~H"""
    <div class={"rounded-full flex-shrink-0 #{@class} #{status_dot_class(@status)}"} />
    """
  end

  defp status_dot_class("working"), do: "bg-success animate-pulse"
  defp status_dot_class("waiting"), do: "bg-warning animate-pulse"
  defp status_dot_class("compacting"), do: "bg-orange-500 animate-pulse"
  defp status_dot_class(_), do: "bg-base-content/20"
end
