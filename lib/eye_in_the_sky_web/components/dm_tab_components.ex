defmodule EyeInTheSkyWeb.Components.DmTabComponents do
  @moduledoc """
  Tab content components for the DM page.

  Covers all five tabs: messages, tasks, commits, notes, timeline.

  Imported by DmPage so all <.tab_name ...> call-sites are unchanged.
  """

  use EyeInTheSkyWeb, :html

  import EyeInTheSkyWeb.Components.DmHelpers
  import EyeInTheSkyWeb.Components.DmMessageComponents

  alias EyeInTheSky.Tasks.WorkflowState

  # ---------------------------------------------------------------------------
  # messages_tab
  # ---------------------------------------------------------------------------

  attr :messages, :list, default: []
  attr :has_more_messages, :boolean, default: false
  attr :show_live_stream, :boolean, default: false
  attr :stream_content, :string, default: ""
  attr :stream_tool, :string, default: nil
  attr :stream_thinking, :string, default: nil
  attr :session, :map, default: nil
  attr :agent, :map, default: nil

  def messages_tab(assigns) do
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

  # ---------------------------------------------------------------------------
  # tasks_tab
  # ---------------------------------------------------------------------------

  attr :tasks, :list, default: []

  def tasks_tab(assigns) do
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
                        <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-info opacity-50">
                        </span>
                        <span class="relative inline-flex rounded-full h-2 w-2 bg-info"></span>
                      </span>
                    <% else %>
                      <span class={[
                        "inline-flex rounded-full h-2 w-2",
                        task.state_id == WorkflowState.done_id() && "bg-success",
                        task.state_id == WorkflowState.in_review_id() && "bg-warning",
                        task.state_id not in [
                          WorkflowState.in_progress_id(),
                          WorkflowState.done_id(),
                          WorkflowState.in_review_id()
                        ] && "bg-base-content/20"
                      ]}>
                      </span>
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
                          task.state_id not in [
                            WorkflowState.in_progress_id(),
                            WorkflowState.done_id(),
                            WorkflowState.in_review_id()
                          ] && "text-base-content/45"
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
                      <div class="text-sm text-base-content/65 leading-relaxed whitespace-pre-wrap mb-2">
                        {String.trim(task.description)}
                      </div>
                    <% end %>
                    <%= for note <- Map.get(task, :notes, []) do %>
                      <div class="mt-1.5 rounded-lg bg-base-200/60 px-3 py-2">
                        <%= if note.title do %>
                          <div class="text-[11px] font-semibold text-base-content/60 mb-0.5">
                            {note.title}
                          </div>
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
        <.icon name="hero-plus" class="w-4 h-4" /> Add task
      </button>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # commits_tab
  # ---------------------------------------------------------------------------

  attr :commits, :list, default: []
  attr :diff_cache, :map, default: %{}

  def commits_tab(assigns) do
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

  # ---------------------------------------------------------------------------
  # notes_tab
  # ---------------------------------------------------------------------------

  attr :notes, :list, default: []

  def notes_tab(assigns) do
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

  # ---------------------------------------------------------------------------
  # timeline_tab
  # ---------------------------------------------------------------------------

  attr :checkpoints, :list, default: []
  attr :show_create_checkpoint, :boolean, default: false

  def timeline_tab(assigns) do
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
end
