defmodule EyeInTheSkyWeb.Components.DmPage do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  alias EyeInTheSky.Settings.JsonSettings
  alias EyeInTheSkyWeb.Components.DmPage.ActionMenu
  alias EyeInTheSkyWeb.Components.DmPage.CommitsTab
  alias EyeInTheSkyWeb.Components.DmPage.Composer
  alias EyeInTheSkyWeb.Components.DmPage.ContextTab
  alias EyeInTheSkyWeb.Components.DmPage.MessagesTab
  alias EyeInTheSkyWeb.Components.DmPage.NotesTab
  alias EyeInTheSkyWeb.Components.DmPage.SettingsTab
  alias EyeInTheSkyWeb.Components.DmPage.TasksTab
  alias EyeInTheSkyWeb.Components.DmPage.ToolsTab

  @tabs [
    {"messages", "hero-chat-bubble-left-right", "Chat"},
    {"tasks", "hero-clipboard-document-list", "Tasks"},
    {"commits", "hero-code-bracket", "Commits"},
    {"notes", "hero-document-text", "Notes"},
    {"context", "hero-document-magnifying-glass", "Context"},
    {"tools", "hero-wrench-screwdriver", "Tools"},
    {"settings", "hero-cog-6-tooth", "Settings"}
  ]

  attr :agent, :map, required: true
  attr :session_uuid, :string, required: true
  attr :active_tab, :string, required: true
  attr :uploads, :map, required: true
  attr :stream, :map, default: %{show: false, content: "", tool: nil, thinking: nil}
  attr :session_state, :map, required: true
  attr :commits, :list, default: []
  attr :diff_cache, :map, default: %{}
  attr :commits_view, :atom, default: :list
  attr :diff_mode, :atom, default: :unified
  attr :cumulative_diff, :any, default: nil
  attr :notes, :list, default: []
  attr :codex_raw_lines, :list, default: []
  attr :slash_items, :list, default: []
  attr :session_context, :map, default: nil
  attr :agent_record, :map, default: nil
  attr :notify_on_stop, :boolean, default: false
  attr :dm_settings_scope, :string, default: "session"
  attr :dm_settings_subtab, :string, default: "general"
  attr :dm_settings_effective, :map, default: %{}
  # LiveView streams - passed through to MessagesTab so it can render the
  # phx-update="stream" container without holding @messages itself.
  attr :streams, :map, required: true
  # Grouped maps replacing 10 individual attrs
  attr :message_data, :map,
    default: %{
      messages: [],
      has_more_messages: false,
      message_search_query: "",
      queued_prompts: []
    }

  attr :task_data, :map, default: %{tasks: [], current_task: nil}

  attr :overlay_data, :map, default: %{active_overlay: nil, active_timer: nil, reloading: false}
  attr :syncing, :boolean, default: false
  attr :pty_pid, :any, default: nil
  attr :session_init_data, :map, default: nil

  defp normalize_message_data(message_data) do
    Map.merge(
      %{messages: [], has_more_messages: false, message_search_query: "", queued_prompts: []},
      message_data
    )
  end

  def dm_page(assigns) do
    # Compute agent-only effective settings (defaults ⊕ agent, no session override).
    # @agent is the session struct; @agent_record is the actual agent struct.
    agent_settings = (assigns.agent_record && assigns.agent_record.settings) || %{}
    session_settings = (assigns.agent && assigns.agent.settings) || %{}

    # Override indicators: leaf keys the session has explicitly set.
    overrides =
      Enum.flat_map(session_settings, fn
        {_ns, map} when is_map(map) -> Map.keys(map)
        _ -> []
      end)

    assigns =
      assigns
      |> assign(:tabs, @tabs)
      |> update(:message_data, &normalize_message_data/1)
      |> assign(
        :dm_settings_agent_effective,
        JsonSettings.effective_settings(agent_settings, %{})
      )
      |> assign(:dm_settings_overrides, overrides)

    ~H"""
    <div
      class={[
        "flex flex-col h-full relative overflow-hidden",
        if(@pty_pid, do: "px-0 py-0", else: "px-0 sm:px-4 lg:px-8 py-0 sm:py-4"),
        if(@pty_pid, do: "pty-content", else: nil)
      ]}
      style={if @pty_pid, do: "background: var(--pty-bg, #1e1e1e)", else: nil}
      id="dm-page"
      phx-drop-target={@uploads.files.ref}
      phx-hook="DragUpload"
    >
      <%!-- Create note modal --%>
      <%= if @overlay_data.active_overlay == :create_note do %>
        <div class="modal modal-open modal-bottom sm:modal-middle" id="create-note-modal">
          <div class="modal-box w-full sm:max-w-sm pb-[env(safe-area-inset-bottom)]">
            <h3 class="font-semibold text-message mb-3">Create Note</h3>

            <form id="create-note-form" phx-submit="create_note">
              <div class="mb-4">
                <label class="text-mini font-medium text-base-content/60 mb-1.5 block">
                  Title <span class="text-base-content/30">(optional)</span>
                </label>
                <input
                  type="text"
                  name="title"
                  class="input input-bordered w-full text-message"
                  placeholder="Note title..."
                  maxlength="255"
                />
              </div>

              <div class="mb-4">
                <label class="text-mini font-medium text-base-content/60 mb-1.5 block">
                  Note
                </label>
                <textarea
                  name="body"
                  rows="6"
                  class="textarea textarea-bordered w-full text-message resize-none"
                  placeholder="Write your note..."
                  required
                ></textarea>
              </div>

              <div class="modal-action">
                <button
                  type="button"
                  phx-click="close_create_note_modal"
                  class="btn btn-ghost btn-sm min-h-[44px]"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="btn btn-primary btn-sm min-h-[44px]"
                >
                  Create Note
                </button>
              </div>
            </form>
          </div>
          <div class="modal-backdrop" phx-click="close_create_note_modal"></div>
        </div>
      <% end %>

      <%!-- Reload confirm modal --%>
      <dialog
        id="dm-reload-confirm-modal"
        class="modal modal-bottom sm:modal-middle"
        phx-hook="ReloadConfirmModal"
      >
        <div class="modal-box pb-[env(safe-area-inset-bottom)]">
          <h3 class="font-semibold text-message">Reload from file?</h3>
          <p class="py-3 text-message text-base-content/70">
            This will <strong class="text-warning">delete all messages</strong>
            and re-import from the transcript file. Use "Sync messages" instead if you only want to recover missed messages.
          </p>
          <div class="form-control mb-4">
            <label class="label cursor-pointer gap-2 justify-start min-h-[44px] flex items-center">
              <input type="checkbox" data-reload-skip class="checkbox checkbox-sm" />
              <span class="label-text text-message">Don't show this message again</span>
            </label>
          </div>
          <div class="modal-action">
            <button data-reload-cancel class="btn btn-ghost btn-sm min-h-[44px]">Cancel</button>
            <button data-reload-confirm class="btn btn-error btn-sm min-h-[44px]">Reload</button>
          </div>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button data-reload-cancel>close</button>
        </form>
      </dialog>

      <%!-- Schedule timer modal --%>
      <%= if @overlay_data.active_overlay == :schedule_timer do %>
        <div class="modal modal-open modal-bottom sm:modal-middle" id="schedule-timer-modal">
          <div class="modal-box w-full sm:max-w-sm pb-[env(safe-area-inset-bottom)]">
            <h3 class="font-semibold text-message mb-3">
              {if @overlay_data.active_timer, do: "Edit Scheduled Message", else: "Schedule Message"}
            </h3>

            <form id="schedule-timer-form" phx-submit="schedule_timer">
              <input type="hidden" name="mode" id="timer-mode-input" value="once" />
              <input type="hidden" name="preset" id="timer-preset-input" value="15m" />

              <div class="mb-4">
                <label class="text-mini font-medium text-base-content/60 mb-1.5 block">Message</label>
                <textarea
                  name="message"
                  rows="3"
                  class="textarea textarea-bordered w-full text-message resize-none"
                  placeholder="Message to send when timer fires..."
                ><%= if @overlay_data.active_timer, do: @overlay_data.active_timer.message, else: EyeInTheSky.OrchestratorTimers.default_message() %></textarea>
              </div>

              <div class="mb-3">
                <p class="text-mini font-medium text-base-content/60 mb-2">Once</p>
                <div class="flex flex-wrap gap-1.5">
                  <%= for preset <- ["5m", "10m", "15m", "30m", "1h"] do %>
                    <button
                      type="submit"
                      phx-click={
                        JS.set_attribute({"value", "once"}, to: "#timer-mode-input")
                        |> JS.set_attribute({"value", preset}, to: "#timer-preset-input")
                      }
                      class="btn btn-sm btn-outline"
                    >
                      {preset}
                    </button>
                  <% end %>
                </div>
              </div>

              <div class="mb-4">
                <p class="text-mini font-medium text-base-content/60 mb-2">Repeating</p>
                <div class="flex flex-wrap gap-1.5">
                  <%= for preset <- ["5m", "10m", "15m", "30m", "1h"] do %>
                    <button
                      type="submit"
                      phx-click={
                        JS.set_attribute({"value", "repeating"}, to: "#timer-mode-input")
                        |> JS.set_attribute({"value", preset}, to: "#timer-preset-input")
                      }
                      class="btn btn-sm btn-outline"
                    >
                      {preset}
                    </button>
                  <% end %>
                </div>
              </div>

              <div class="modal-action">
                <button
                  type="button"
                  phx-click="close_schedule_modal"
                  class="btn btn-ghost btn-sm min-h-[44px]"
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>
          <div class="modal-backdrop" phx-click="close_schedule_modal"></div>
        </div>
      <% end %>

      <%!-- Reload loading overlay --%>
      <div
        :if={@overlay_data.reloading}
        class="absolute inset-0 z-40 flex items-center justify-center bg-base-100/80 backdrop-blur-sm rounded-box"
      >
        <div class="flex flex-col items-center gap-3">
          <span class="loading loading-spinner loading-lg text-primary"></span>
          <p class="text-message text-base-content/60">Reloading messages...</p>
        </div>
      </div>

      <%!-- Drag overlay --%>
      <div
        id="drag-overlay"
        class="absolute inset-0 z-50 hidden pointer-events-none rounded-box"
      >
        <div class="absolute inset-3 rounded-box border-2 border-dashed border-primary/40 bg-primary/[0.04] flex items-center justify-center">
          <div class="text-center">
            <.icon name="hero-arrow-up-tray" class="w-10 h-10 text-primary/50 mx-auto mb-2" />
            <p class="text-message font-medium text-primary/60">Drop files to attach</p>
          </div>
        </div>
      </div>

      <%!-- Mobile slim top bar --%>
      <div class="md:hidden sticky top-0 z-30 flex-shrink-0 flex items-center gap-1 px-2 pt-[env(safe-area-inset-top)] h-[calc(3rem+env(safe-area-inset-top))] border-b border-base-content/8 bg-base-100">
        <button
          phx-click={Phoenix.LiveView.JS.dispatch("rail:open", to: "#rail-root")}
          class="btn btn-ghost btn-square w-10 h-10 text-base-content/60 focus-ring"
          aria-label="Open menu"
        >
          <.icon name="hero-bars-3" class="size-5" />
        </button>
        <div class="flex-1 flex items-center justify-center gap-1.5 min-w-0 px-1">
          <.status_dot
            status={@agent.status}
            size="xs"
            animate={@agent.status in ~w(working waiting compacting)}
          />
          <%= if @agent.entrypoint == "cli" do %>
            <.icon name="hero-command-line" class="size-3.5 text-base-content/40 flex-shrink-0" />
          <% end %>
          <div class="flex flex-col items-center min-w-0 flex-1">
            <input
              type="text"
              value={@agent.name || ""}
              placeholder="Session name"
              phx-blur="update_session_name"
              phx-keydown={JS.push("update_session_name") |> JS.focus(to: "#message-input")}
              phx-key="Enter"
              class="text-message font-semibold text-base-content/85 bg-transparent border-0 outline-none focus:outline-none focus:ring-0 focus:bg-base-content/5 rounded-box px-1 -mx-1 min-w-0 w-full text-center placeholder:text-base-content/20 transition-colors"
            />
            <%= if @agent_record && Ecto.assoc_loaded?(@agent_record.agent_definition) && @agent_record.agent_definition && @agent_record.agent_definition.display_name do %>
              <span class="text-mini text-base-content/35 truncate">
                {@agent_record.agent_definition.display_name}
              </span>
            <% end %>
          </div>
        </div>
        <ActionMenu.action_menu
          button_class="btn btn-ghost btn-square w-10 h-10 text-base-content/60 focus-ring"
          show_tabs={true}
          tabs={@tabs}
          active_tab={@active_tab}
          reload_label="Reload from file"
          show_iterm={true}
          show_push_setup={true}
          notify_on_stop={@notify_on_stop}
          active_timer={@overlay_data.active_timer}
          schedule_btn_id="dm-schedule-timer-btn"
          cancel_btn_id="dm-cancel-timer-btn"
          session_uuid={@session_uuid}
          session_active={@agent.status in ~w(working compacting)}
        />
      </div>

      <%!-- Header card (desktop only) --%>
      <div
        class="hidden max-w-6xl mx-auto w-full bg-base-200 rounded-box border border-base-content/10 shadow-sm mb-3 flex-shrink-0"
        id="dm-header-card"
      >
        <div class="px-4 sm:px-5 py-3" id="dm-header">
          <div class="flex items-center gap-2 min-w-0">
            <div class="flex items-start gap-2 min-w-0 flex-1">
              <.status_dot
                status={@agent.status}
                animate={@agent.status in ~w(working waiting compacting)}
                class="mt-[5px]"
              />
              <div class="flex flex-col min-w-0 flex-1">
                <div class="flex items-center gap-2 min-w-0">
                  <%= if @agent.entrypoint == "cli" do %>
                    <.icon
                      name="hero-command-line"
                      class="size-4 text-base-content/40 flex-shrink-0"
                    />
                  <% end %>
                  <input
                    type="text"
                    value={@agent.name || ""}
                    placeholder="Session name"
                    phx-blur="update_session_name"
                    phx-keydown={JS.push("update_session_name") |> JS.focus(to: "#message-input")}
                    phx-key="Enter"
                    class="text-message sm:text-lg font-bold text-base-content bg-transparent border-0 outline-none focus:outline-none focus:ring-0 focus:bg-base-content/5 rounded-box px-1 -mx-1 min-w-0 flex-1 placeholder:text-base-content/20 transition-colors"
                  />
                </div>
                <input
                  type="text"
                  value={@agent.description || ""}
                  placeholder="Add a description..."
                  phx-blur="update_session_description"
                  phx-keydown="update_session_description"
                  phx-key="Enter"
                  class="text-message text-base-content/40 bg-transparent border-0 outline-none focus:outline-none focus:ring-0 focus:bg-base-content/5 rounded-box px-1 -mx-1 placeholder:text-base-content/20 transition-colors w-full"
                />
              </div>
            </div>
            <div class="flex items-center gap-1 flex-shrink-0">
              <%!-- Active timer badge --%>
              <%= if @overlay_data.active_timer do %>
                <button
                  type="button"
                  phx-click="open_schedule_timer"
                  class="hidden sm:flex items-center gap-1.5 px-2 py-1 rounded-box bg-warning/10 text-warning text-mini font-medium hover:bg-warning/20 transition-colors"
                  title="Edit scheduled message"
                >
                  <.icon name="hero-clock" class="size-3.5" />
                  <span>{if @overlay_data.active_timer.mode == :once, do: "Once"}</span>
                  <span
                    id="timer-countdown"
                    phx-hook="TimerCountdown"
                    data-fire-at={DateTime.to_iso8601(@overlay_data.active_timer.next_fire_at)}
                  >
                    --:--
                  </span>
                </button>
              <% end %>

              <%!-- Unified hamburger menu (desktop + mobile) --%>
              <ActionMenu.action_menu
                wrapper_id="dm-actions-menu"
                button_class="btn btn-ghost btn-square w-9 h-9 text-base-content/60"
                show_jsonl_export={true}
                show_push_setup={true}
                show_iterm={true}
                reload_label="Reload from file"
                active_timer={@overlay_data.active_timer}
                cancel_btn_id="dm-cancel-timer-btn-desktop"
                notify_on_stop={@notify_on_stop}
                session_uuid={@session_uuid}
                session_active={@agent.status in ~w(working compacting)}
              />
            </div>
          </div>
        </div>

        <%!-- Current task strip --%>
        <%= if is_struct(@task_data.current_task) do %>
          <div class="px-5 py-2 border-t border-base-content/5" id="dm-current-task">
            <div class="flex items-center gap-2">
              <span class="text-mini font-semibold uppercase tracking-normal text-base-content/30 flex-shrink-0">
                Working on
              </span>
              <div class="flex items-center gap-1.5 min-w-0">
                <div class="w-1.5 h-1.5 rounded-full bg-info animate-pulse flex-shrink-0" />
                <span class="text-mini font-medium text-base-content/70 truncate">
                  {@task_data.current_task.title}
                </span>
              </div>
              <span class="flex-shrink-0 text-mini text-base-content/25 font-mono">
                {String.slice(to_string(@task_data.current_task.id), 0..7)}
              </span>
            </div>
          </div>
        <% end %>

        <%!-- Compacting indicator --%>
        <%= if @session_state.compacting do %>
          <div
            class="px-5 py-2 border-t border-warning/20 bg-warning/5"
            id="dm-compacting-strip"
          >
            <div class="flex items-center gap-2">
              <div class="w-1.5 h-1.5 rounded-full bg-warning animate-pulse flex-shrink-0" />
              <span class="text-mini font-medium text-warning/80">Compacting context...</span>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @pty_pid do %>
        <%!-- PTY terminal - always in DOM so xterm.js keeps its state; hidden when off messages tab --%>
        <div
          id={"pty-dm-#{@session_uuid}"}
          phx-hook="PtyHook"
          phx-update="ignore"
          class="flex-1 min-h-0 p-2 overflow-hidden"
          style={if @active_tab not in ["messages", nil], do: "display:none"}
        >
        </div>
      <% end %>
      <%= if !@pty_pid || @active_tab not in ["messages", nil] do %>
        <%!-- Tab content - shown when no PTY, or PTY active but on non-messages tab --%>
        <div
          class="flex-1 min-h-0 max-w-6xl mx-auto w-full overflow-y-auto flex flex-col"
          id="dm-tab-content"
        >
          <%= case @active_tab do %>
            <% "messages" -> %>
              <.messages_tab_content
                streams={@streams}
                message_data={@message_data}
                stream={@stream}
                agent={@agent}
                codex_raw_lines={@codex_raw_lines}
                session_state={@session_state}
                syncing={@syncing}
              />
            <% "tasks" -> %>
              <TasksTab.tasks_tab tasks={@task_data.tasks} />
            <% "commits" -> %>
              <CommitsTab.commits_tab
                commits={@commits}
                diff_cache={@diff_cache}
                commits_view={@commits_view}
                diff_mode={@diff_mode}
                cumulative_diff={@cumulative_diff}
              />
            <% "notes" -> %>
              <NotesTab.notes_tab notes={@notes} />
            <% "context" -> %>
              <ContextTab.context_tab session_context={@session_context} />
            <% "tools" -> %>
              <ToolsTab.tools_tab session_init_data={@session_init_data} />
            <% "settings" -> %>
              <SettingsTab.settings_tab
                scope={@dm_settings_scope}
                subtab={@dm_settings_subtab}
                session={@agent}
                agent={@agent_record}
                session_state={@session_state}
                notify_on_stop={@notify_on_stop}
                effective={@dm_settings_effective}
                agent_effective={@dm_settings_agent_effective}
                overrides={@dm_settings_overrides}
              />
            <% _ -> %>
              <.messages_tab_content
                streams={@streams}
                message_data={@message_data}
                stream={@stream}
                agent={@agent}
                codex_raw_lines={@codex_raw_lines}
                session_state={@session_state}
                syncing={@syncing}
              />
          <% end %>
        </div>

        <%!-- Composer (pinned to bottom) --%>
        <%= if @active_tab in ["messages", nil] do %>
          <div
            id="dm-page-composer"
            class="flex-shrink-0 max-w-[860px] mx-auto w-full px-5 pb-7 pt-3 safe-inset-bottom"
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
              show_thinking_blocks={Map.get(@session_state, :show_thinking_blocks, false)}
              max_budget_usd={@session_state.max_budget_usd}
              provider={@agent.provider}
              context_used={@session_state.context_used}
              context_window={@session_state.context_window}
              total_cost={Map.get(@session_state, :total_cost, 0.0)}
              display_name={
                if @agent_record && Ecto.assoc_loaded?(@agent_record.agent_definition) &&
                     @agent_record.agent_definition,
                   do: @agent_record.agent_definition.display_name
              }
              session_cli_opts={assigns[:session_cli_opts] || []}
              session_uuid={@session_uuid}
            />
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :streams, :map, required: true
  attr :message_data, :map, required: true
  attr :stream, :map, required: true
  attr :agent, :map, required: true
  attr :codex_raw_lines, :list, required: true
  attr :session_state, :map, default: %{}
  attr :syncing, :boolean, default: false

  defp messages_tab_content(assigns) do
    ~H"""
    <MessagesTab.messages_tab
      streams={@streams}
      empty={@message_data.messages == []}
      has_more_messages={@message_data.has_more_messages}
      stream={@stream}
      session={@agent}
      agent={@agent}
      message_search_query={@message_data.message_search_query}
      codex_raw_lines={@codex_raw_lines}
      show_thinking_blocks={Map.get(@session_state, :show_thinking_blocks, false)}
      syncing={@syncing}
    />
    """
  end
end
