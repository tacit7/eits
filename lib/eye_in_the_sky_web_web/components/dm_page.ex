defmodule EyeInTheSkyWebWeb.Components.DmPage do
  @moduledoc false

  use EyeInTheSkyWebWeb, :html

  @tabs [
    {"messages", "hero-chat-bubble-left-right", "Messages"},
    {"tasks", "hero-clipboard-document-list", "Tasks"},
    {"commits", "hero-code-bracket", "Commits"},
    {"logs", "hero-command-line", "Logs"},
    {"notes", "hero-document-text", "Notes"}
  ]

  attr :agent, :map, required: true
  attr :session_uuid, :string, required: true
  attr :active_tab, :string, required: true
  attr :messages, :list, default: []
  attr :has_more_messages, :boolean, default: false
  attr :uploads, :map, required: true
  attr :selected_model, :string, default: "opus"
  attr :selected_effort, :string, default: ""
  attr :show_model_menu, :boolean, default: false
  attr :processing, :boolean, default: false
  attr :tasks, :list, default: []
  attr :commits, :list, default: []
  attr :logs, :list, default: []
  attr :notes, :list, default: []
  attr :show_live_stream, :boolean, default: false
  attr :stream_content, :string, default: ""
  attr :stream_tool, :string, default: nil
  attr :slash_items, :list, default: []

  def dm_page(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <div class="flex flex-col h-[calc(100vh-2rem)] px-4 sm:px-6 lg:px-8 py-4" id="dm-page">
      <%!-- Header card --%>
      <div
        class="max-w-6xl mx-auto w-full bg-base-100 dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl border border-base-content/5 shadow-sm mb-3 flex-shrink-0"
        id="dm-header-card"
      >
        <div class="px-5 py-3" id="dm-header">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <div class={"w-2 h-2 rounded-full flex-shrink-0 " <> if(is_nil(@agent.ended_at) || @agent.ended_at == "", do: "bg-success animate-pulse", else: "bg-base-content/20")} />
              <h1 class="text-lg font-bold text-base-content">{@agent.name || "Session"}</h1>
              <button
                type="button"
                class="flex items-center gap-1 text-[11px] font-mono text-base-content/30 bg-base-content/5 px-2 py-0.5 rounded hover:text-base-content/50 hover:bg-base-content/8 transition-colors cursor-pointer"
                phx-hook="CopyToClipboard"
                id="copy-session-uuid"
                data-copy={@session_uuid}
              >
                {String.slice(@session_uuid, 0..7)}
                <.icon name="hero-clipboard-document" class="w-3 h-3" />
              </button>
            </div>
            <div class="flex items-center gap-2">
              <button
                phx-click="toggle_live_stream"
                phx-hook="LiveStreamToggle"
                id="dm-live-stream-toggle"
                class={[
                  "flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs transition-colors",
                  @show_live_stream && "text-primary bg-primary/10 hover:bg-primary/15",
                  !@show_live_stream &&
                    "text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5"
                ]}
              >
                <.icon
                  name={if @show_live_stream, do: "hero-signal-solid", else: "hero-signal"}
                  class="w-3.5 h-3.5"
                /> Live
              </button>
              <button
                phx-click="reload_from_session_file"
                data-confirm="This will delete all messages and re-import from the JSONL file. Continue?"
                class="flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 transition-colors"
                id="dm-reload-button"
              >
                <.icon name="hero-arrow-path" class="w-3.5 h-3.5" /> Reload
              </button>
            </div>
          </div>
        </div>

        <%!-- Pill tabs --%>
        <div class="px-5 pb-3" id="dm-tabs">
          <div class="flex items-center gap-1 bg-base-content/[0.03] rounded-lg p-0.5">
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
            />
          <% "tasks" -> %>
            <.tasks_tab tasks={@tasks} />
          <% "commits" -> %>
            <.commits_tab commits={@commits} />
          <% "logs" -> %>
            <.logs_tab logs={@logs} />
          <% "notes" -> %>
            <.notes_tab notes={@notes} />
          <% _ -> %>
            <.messages_tab
              messages={@messages}
              has_more_messages={@has_more_messages}
              show_live_stream={@show_live_stream}
              stream_content={@stream_content}
              stream_tool={@stream_tool}
            />
        <% end %>
      </div>

      <%!-- Composer (pinned to bottom) --%>
      <%= if @active_tab in ["messages", nil] do %>
        <div class="flex-shrink-0 max-w-4xl mx-auto w-full pt-2">
          <.message_form
            uploads={@uploads}
            selected_model={@selected_model}
            selected_effort={@selected_effort}
            show_model_menu={@show_model_menu}
            processing={@processing}
            slash_items={@slash_items}
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

  defp messages_tab(assigns) do
    ~H"""
    <div class="flex h-full flex-col" id="dm-messages-tab">
      <div class="flex-1 min-h-0 flex flex-col">
        <div
          class="px-4 py-2 overflow-y-auto flex-1 min-h-0"
          id="messages-container"
          phx-hook="ScrollToBottom"
          style="scrollbar-width: none; -ms-overflow-style: none;"
        >
          <%= if @messages == [] do %>
            <div class="flex flex-col items-center justify-center py-16 text-center">
              <.icon name="hero-chat-bubble-left-right" class="w-8 h-8 text-base-content/15 mb-3" />
              <p class="text-sm text-base-content/40">No messages yet</p>
              <p class="mt-1 text-xs text-base-content/25">
                Send a message to start the conversation
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
            <%= if @show_live_stream && (@stream_content != "" || @stream_tool) do %>
              <div class="py-3 px-2" id="live-stream-bubble">
                <div class="flex items-start gap-2.5">
                  <img
                    src="/images/claude.svg"
                    class="w-4 h-4 mt-1 flex-shrink-0 animate-pulse"
                    alt="Claude"
                  />
                  <div class="min-w-0 flex-1">
                    <span class="text-[13px] font-semibold text-primary/80">Agent</span>
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
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :message, :map, required: true

  defp message_item(assigns) do
    is_user = assigns.message.sender_role == "user"
    assigns = assign(assigns, :is_user, is_user)

    ~H"""
    <div
      class={[
        "py-3 px-2 -mx-2 rounded-lg transition-colors",
        !@is_user && "bg-primary/[0.03]",
        @is_user && "hover:bg-base-content/[0.02]"
      ]}
      id={"dm-message-#{@message.id}"}
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
          <div class="flex items-baseline gap-2">
            <span class={[
              "text-[13px] font-semibold",
              !@is_user && "text-primary/80",
              @is_user && "text-base-content/70"
            ]}>
              {message_sender_name(@message)}
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
            <span class="text-[11px] text-base-content/25">{format_time(@message.inserted_at)}</span>
          </div>

          <div
            id={"msg-body-#{@message.id}"}
            class="dm-markdown mt-1 text-sm leading-relaxed text-base-content/85"
            phx-hook="MarkdownMessage"
            data-raw-body={@message.body}
          >
          </div>

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

  attr :uploads, :map, required: true
  attr :selected_model, :string, default: "opus"
  attr :selected_effort, :string, default: ""
  attr :show_model_menu, :boolean, default: false
  attr :processing, :boolean, default: false
  attr :slash_items, :list, default: []

  defp message_form(assigns) do
    ~H"""
    <form
      phx-submit="send_message"
      phx-change="validate_upload"
      class="rounded-2xl border border-base-content/10 bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] shadow-sm"
      id="message-form"
      data-slash-items={Jason.encode!(@slash_items)}
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
          placeholder={if @processing, do: "Agent is working...", else: "Reply..."}
          class="w-full bg-transparent border-0 outline-none focus:ring-0 text-sm resize-none min-h-[28px] max-h-40 overflow-y-hidden placeholder:text-base-content/30 p-0"
          autocomplete="off"
          disabled={@processing}
          phx-hook="CommandHistory"
          id="message-input"
        ></textarea>
      </div>

      <%!-- Bottom toolbar --%>
      <div class="flex items-center justify-between px-3 pb-3 pt-1" id="dm-composer-toolbar">
        <%!-- Left: upload button --%>
        <div class="flex items-center">
          <label
            for={@uploads.files.ref}
            phx-drop-target={@uploads.files.ref}
            class="flex items-center justify-center w-8 h-8 rounded-lg cursor-pointer text-base-content/30 hover:text-base-content/60 hover:bg-base-content/5 transition-colors"
          >
            <.icon name="hero-plus" class="w-5 h-5" />
          </label>
          <.live_file_input upload={@uploads.files} class="hidden" />
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
                class="dropdown-content menu z-[1] w-64 rounded-xl border border-base-content/8 bg-base-100 p-1.5 shadow-lg"
                id="model-selector-menu"
              >
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
              </ul>
            <% end %>
          </div>

          <%!-- Send / Stop button --%>
          <%= if @processing do %>
            <button
              type="button"
              phx-click="kill_session"
              class="flex items-center justify-center w-8 h-8 rounded-lg bg-error/80 text-error-content hover:bg-error transition-colors"
              id="dm-stop-button"
            >
              <.icon name="hero-stop-solid" class="w-4 h-4" />
            </button>
          <% else %>
            <button
              type="submit"
              class="flex items-center justify-center w-8 h-8 rounded-lg bg-primary/70 text-primary-content hover:bg-primary transition-colors"
              id="dm-send-button"
            >
              <.icon name="hero-arrow-up-mini" class="w-5 h-5" />
            </button>
          <% end %>
        </div>
      </div>
    </form>
    """
  end

  attr :tasks, :list, default: []

  defp tasks_tab(assigns) do
    ~H"""
    <%= if @tasks == [] do %>
      <.empty_state
        id="dm-tasks-empty"
        icon="hero-clipboard-document-list"
        title="No tasks yet"
        subtitle="Tasks from this session will appear here"
      />
    <% else %>
      <div
        class="space-y-1 bg-[oklch(95%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl shadow-sm p-4"
        id="dm-task-list"
      >
        <%= for task <- @tasks do %>
          <div
            class="collapse collapse-arrow rounded-lg border border-base-content/5 bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] hover:border-base-content/10 transition-colors"
            id={"dm-task-#{task.id}"}
          >
            <input type="checkbox" />
            <div class="collapse-title py-3 px-4 min-h-0">
              <div class="flex items-center gap-3">
                <.icon
                  name="hero-clipboard-document-list"
                  class="h-4 w-4 flex-shrink-0 text-base-content/30"
                />
                <div class="flex-1 min-w-0">
                  <h3 class="text-[13px] font-semibold text-base-content/85 truncate">
                    {task.title}
                  </h3>
                  <div class="flex items-center gap-1.5 mt-0.5 text-[11px] text-base-content/30">
                    <span class="font-mono">
                      {String.slice(task.uuid || to_string(task.id), 0..7)}
                    </span>
                    <%= if task.state do %>
                      <span class="text-base-content/15">/</span>
                      <span class="font-medium">{task.state.name}</span>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
            <div class="collapse-content px-4 pb-4">
              <div class="pl-[30px]">
                <div class="whitespace-pre-wrap text-sm text-base-content/70 leading-relaxed">
                  {task.description || "No description"}
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :commits, :list, default: []

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
        class="space-y-1 bg-[oklch(95%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl shadow-sm p-4"
        id="dm-commit-list"
      >
        <%= for commit <- @commits do %>
          <div
            class="collapse collapse-arrow rounded-lg border border-base-content/5 bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] hover:border-base-content/10 transition-colors"
            id={"dm-commit-#{commit.id}"}
          >
            <input type="checkbox" />
            <div class="collapse-title py-3 px-4 min-h-0">
              <div class="flex items-center gap-3">
                <.icon name="hero-code-bracket" class="h-4 w-4 flex-shrink-0 text-base-content/30" />
                <div class="flex-1 min-w-0">
                  <h3 class="text-[13px] font-semibold text-base-content/85 truncate">
                    {extract_commit_title(commit.commit_message)}
                  </h3>
                  <div class="flex items-center gap-1.5 mt-0.5 text-[11px] text-base-content/30">
                    <span class="font-mono">{String.slice(commit.commit_hash || "", 0..7)}</span>
                    <span class="text-base-content/15">/</span>
                    <span class="tabular-nums">{format_note_timestamp(commit.created_at)}</span>
                  </div>
                </div>
              </div>
            </div>
            <div class="collapse-content px-4 pb-4">
              <div class="pl-[30px]">
                <pre class="whitespace-pre-wrap font-mono text-sm text-base-content/70 leading-relaxed"><%= commit.commit_message %></pre>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :logs, :list, default: []

  defp logs_tab(assigns) do
    ~H"""
    <%= if @logs == [] do %>
      <.empty_state
        id="dm-logs-empty"
        icon="hero-command-line"
        title="No logs"
        subtitle="Logs from this session will appear here"
      />
    <% else %>
      <div
        class="space-y-1 bg-[oklch(95%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl shadow-sm p-4"
        id="dm-log-list"
      >
        <%= for log <- @logs do %>
          <div
            class="rounded-lg border border-base-content/5 bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] px-4 py-3"
            id={"dm-log-#{log.id}"}
          >
            <div class="text-sm text-base-content/70 font-mono">{log.message}</div>
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
        class="space-y-1 bg-[oklch(95%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl shadow-sm p-4"
        id="dm-note-list"
      >
        <%= for note <- @notes do %>
          <div
            class="collapse collapse-arrow rounded-lg border border-base-content/5 bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] hover:border-base-content/10 transition-colors"
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
                    <span class="tabular-nums">{format_note_timestamp(note.created_at)}</span>
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

  defp message_sender_name(%{sender_role: "user"}), do: "You"
  defp message_sender_name(message), do: message.provider || "Agent"

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

  defp format_time(nil), do: ""

  defp format_time(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} -> format_time(dt)
      _ -> timestamp
    end
  end

  defp format_time(%DateTime{} = timestamp) do
    now = DateTime.utc_now()
    time = Calendar.strftime(timestamp, "%I:%M %p")

    cond do
      DateTime.to_date(timestamp) == DateTime.to_date(now) ->
        "Today at #{time}"

      Date.diff(DateTime.to_date(now), DateTime.to_date(timestamp)) == 1 ->
        "Yesterday at #{time}"

      true ->
        Calendar.strftime(timestamp, "%m/%d/%Y %I:%M %p")
    end
  end

  defp format_time(_), do: ""

  defp model_display_name("opus"), do: "Opus 4.6"
  defp model_display_name("sonnet"), do: "Sonnet 4.5"
  defp model_display_name("haiku"), do: "Haiku 4.5"
  defp model_display_name(other), do: other

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_note_timestamp(nil), do: ""
  defp format_note_timestamp(timestamp) when is_binary(timestamp), do: timestamp
  defp format_note_timestamp(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_note_timestamp(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_note_timestamp(_), do: ""

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
end
