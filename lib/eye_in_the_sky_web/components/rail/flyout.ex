defmodule EyeInTheSkyWeb.Components.Rail.Flyout do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Components.Rail.Flyout.AgentsSection
  alias EyeInTheSkyWeb.Components.Rail.Flyout.CanvasSection
  alias EyeInTheSkyWeb.Components.Rail.Flyout.ChatSection
  alias EyeInTheSkyWeb.Components.Rail.Flyout.FilesSection
  alias EyeInTheSkyWeb.Components.Rail.Flyout.Helpers
  alias EyeInTheSkyWeb.Components.Rail.Flyout.JobsSection
  alias EyeInTheSkyWeb.Components.Rail.Flyout.NotesSection
  alias EyeInTheSkyWeb.Components.Rail.Flyout.PromptsSection
  alias EyeInTheSkyWeb.Components.Rail.Flyout.SessionsSection
  alias EyeInTheSkyWeb.Components.Rail.Flyout.SkillsSection
  alias EyeInTheSkyWeb.Components.Rail.Flyout.TasksSection
  alias EyeInTheSkyWeb.Components.Rail.Flyout.TeamsSection
  alias EyeInTheSkyWeb.Components.Rail.Flyout.UsageSection

  attr :open, :boolean, required: true
  # On mobile (<md), the flyout is hidden even when open unless mobile_open is also true.
  # This prevents the 236px panel from compressing content on first load.
  attr :mobile_open, :boolean, default: false
  attr :active_section, :atom, required: true
  attr :sidebar_project, :any, default: nil
  attr :active_channel_id, :any, default: nil
  attr :flyout_sessions, :list, default: []
  attr :flyout_channels, :list, default: []
  attr :unread_counts, :map, default: %{}
  attr :flyout_canvases, :list, default: []
  attr :flyout_teams, :list, default: []
  attr :team_search, :string, default: ""
  attr :team_status, :string, default: "active"
  attr :flyout_tasks, :list, default: []
  attr :task_search, :string, default: ""
  attr :task_state_filter, :any, default: nil
  attr :session_sort, :atom, default: :last_activity
  attr :session_name_filter, :string, default: ""
  attr :session_show, :atom, default: :twenty
  attr :session_scope, :atom, default: :current
  attr :session_project_visible, :map, default: %{}
  attr :session_project_collapsed, :any, default: nil
  attr :projects, :list, default: []
  attr :notification_count, :integer, default: 0
  attr :flyout_agents, :list, default: []
  attr :agent_search, :string, default: ""
  attr :agent_scope, :string, default: "all"
  attr :flyout_notes, :list, default: []
  attr :note_search, :string, default: ""
  attr :note_parent_type, :any, default: nil
  attr :flyout_skills, :list, default: []
  attr :skill_search, :string, default: ""
  attr :skill_scope, :string, default: "all"
  attr :flyout_prompts, :list, default: []
  attr :prompt_search, :string, default: ""
  attr :prompt_scope, :string, default: "all"
  attr :flyout_jobs, :list, default: []
  attr :flyout_file_nodes, :list, default: []
  attr :flyout_file_expanded, :any, default: nil
  attr :flyout_file_children, :map, default: %{}
  attr :flyout_file_error, :string, default: nil
  attr :flyout_usage, :any, default: nil
  attr :rail_modal, :any, default: nil
  attr :show_new_channel_form, :boolean, default: false
  attr :myself, :any, required: true

  def flyout(assigns) do
    ~H"""
    <div
      data-flyout-panel
      data-vim-flyout-open={to_string(@open)}
      class={
        [
          "flex flex-col border-r border-base-content/8 bg-[var(--surface-flyout)] overflow-hidden flex-shrink-0 transition-[width] duration-150",
          # w-0 is always the mobile base; md:w-[236px] overrides on desktop when open.
          # w-[236px] overrides on mobile only when mobile_open is also true.
          if(@open, do: "w-0 md:w-[236px]", else: "w-0"),
          if(@open && @mobile_open, do: "w-[236px]"),
          # On mobile, sit above the z-40 backdrop so the flyout is interactive.
          # md:z-auto resets to normal stacking on desktop where the backdrop is hidden.
          "z-50 md:z-auto"
        ]
      }
    >
      <div class={["flex flex-col h-full", if(!@open, do: "invisible")]}>
        <%!-- ── Header row: [icon] [Page Name]  [+ button] ── --%>
        <div class="px-2.5 py-2.5 border-b border-base-content/8 flex-shrink-0 flex items-center gap-1">
          <%!-- Icon + label --%>
          <%= cond do %>
            <% @active_section == :agents -> %>
              <Helpers.section_header_link
                route={Helpers.agents_route(@sidebar_project)}
                icon="lucide-robot"
                label="Agents"
                custom={true}
              />
            <% @active_section == :teams -> %>
              <Helpers.section_header_link
                route={Helpers.teams_route(@sidebar_project)}
                icon="hero-users"
                label="Teams"
              />
            <% Helpers.dual_page_section?(@active_section) && Helpers.project_route_for(@active_section, @sidebar_project) -> %>
              <.link
                navigate={Helpers.project_route_for(@active_section, @sidebar_project)}
                title={"#{@sidebar_project.name} #{Helpers.section_label(@active_section)}"}
                class="flex-1 min-w-0 flex items-center gap-1.5 rounded hover:bg-base-content/5 -mx-1 px-1 py-0.5 transition-colors group"
              >
                <span class="flex-shrink-0 flex items-center justify-center text-base-content/35 group-hover:text-base-content/60 transition-colors">
                  <%= if @active_section == :tasks do %>
                    <.custom_icon name="lucide-kanban" class="size-3.5" />
                  <% else %>
                    <.icon name="hero-list-bullet" class="size-3.5" />
                  <% end %>
                </span>
                <span class="text-micro font-semibold uppercase tracking-widest text-base-content/40 group-hover:text-base-content/60 truncate transition-colors">
                  {Helpers.section_label(@active_section)}
                </span>
              </.link>
            <% @active_section == :usage -> %>
              <Helpers.section_header_link route="/usage" icon="hero-chart-bar" label="Usage" />
              <button
                phx-click="refresh_usage"
                phx-target={@myself}
                title="Refresh usage"
                class="size-5 flex items-center justify-center rounded text-base-content/35 hover:text-base-content/70 hover:bg-base-content/8 transition-colors flex-shrink-0"
              >
                <.icon name="hero-arrow-path-mini" class="size-3.5" />
              </button>
            <% @active_section == :chat -> %>
              <Helpers.section_header_link
                route="/chat"
                icon="hero-chat-bubble-left-ellipsis"
                label="Chat"
              />
            <% @active_section == :canvas -> %>
              <Helpers.section_header_link route="/canvases" icon="hero-squares-2x2" label="Canvas" />
            <% @active_section == :skills -> %>
              <Helpers.section_header_link
                route={Helpers.skills_route(@sidebar_project)}
                icon="hero-bolt"
                label="Skills"
              />
            <% true -> %>
              <div class="flex-1 min-w-0 flex items-center gap-1.5">
                <span class="flex-shrink-0 flex items-center justify-center text-base-content/20">
                  <.icon name={Helpers.section_icon(@active_section)} class="size-3.5" />
                </span>
                <span class="text-micro font-semibold uppercase tracking-widest text-base-content/40 truncate">
                  {Helpers.section_label(@active_section)}
                </span>
              </div>
          <% end %>

          <%!-- + / action button (right side of header) --%>
          <%= if @active_section == :notes do %>
            <.header_action_btn phx-click="new_note" phx-target={@myself} title="New note" />
          <% end %>
          <%= if @active_section == :tasks do %>
            <.header_action_btn
              phx-click="open_rail_modal"
              phx-value-type="new_task"
              phx-target={@myself}
              title="New task"
            />
          <% end %>
          <%= if @active_section == :prompts do %>
            <.header_action_btn
              phx-click="open_rail_modal"
              phx-value-type="new_prompt"
              phx-target={@myself}
              title="New prompt"
            />
          <% end %>
          <%= if @active_section == :files do %>
            <button
              phx-click="file_refresh"
              phx-target={@myself}
              title="Refresh file tree"
              class="size-5 flex items-center justify-center rounded text-base-content/35 hover:text-base-content/70 hover:bg-base-content/8 transition-colors flex-shrink-0"
            >
              <.icon name="hero-arrow-path-mini" class="size-3.5" />
            </button>
          <% end %>
          <%= if @active_section == :sessions do %>
            <%= if @sidebar_project do %>
              <.header_action_btn
                phx-click="new_session"
                phx-value-project_id={@sidebar_project.id}
                phx-target={@myself}
                title={"New session in #{@sidebar_project.name}"}
              />
            <% else %>
              <.header_action_btn
                phx-click="toggle_new_session_form"
                phx-target={@myself}
                title="New session"
              />
            <% end %>
          <% end %>
          <%= if @active_section == :chat do %>
            <.header_action_btn
              phx-click="toggle_new_channel_form"
              phx-target={@myself}
              title="New channel"
            />
          <% end %>
        </div>

        <%!-- ── Filter zone (section-specific, always visible) ── --%>
        <%= if @active_section == :sessions do %>
          <SessionsSection.sessions_filters
            session_name_filter={@session_name_filter}
            session_scope={@session_scope}
            myself={@myself}
          />
        <% end %>
        <%= if @active_section == :tasks do %>
          <TasksSection.tasks_filters
            task_search={@task_search}
            state_filter={@task_state_filter}
            myself={@myself}
          />
        <% end %>
        <%= if @active_section == :notes do %>
          <NotesSection.notes_filters
            note_search={@note_search}
            note_parent_type={@note_parent_type}
            myself={@myself}
          />
        <% end %>
        <%= if @active_section == :agents do %>
          <AgentsSection.agents_filters
            agent_search={@agent_search}
            agent_scope={@agent_scope}
            myself={@myself}
          />
        <% end %>
        <%= if @active_section == :skills do %>
          <SkillsSection.skills_filters
            skill_search={@skill_search}
            skill_scope={@skill_scope}
            myself={@myself}
          />
        <% end %>
        <%= if @active_section == :prompts do %>
          <PromptsSection.prompts_filters
            prompt_search={@prompt_search}
            prompt_scope={@prompt_scope}
            myself={@myself}
          />
        <% end %>
        <%= if @active_section == :teams do %>
          <TeamsSection.teams_filters
            team_search={@team_search}
            team_status={@team_status}
            myself={@myself}
          />
        <% end %>

        <%!-- ── Content ── --%>
        <%!-- Sessions manages its own scroll + footer; others use standard overflow wrapper --%>
        <div class={[
          "flex-1 min-h-0",
          if(@active_section == :sessions, do: "flex flex-col", else: "overflow-y-auto py-1")
        ]}>
          <%= case @active_section do %>
            <% :sessions -> %>
              <SessionsSection.sessions_content
                sessions={@flyout_sessions}
                session_name_filter={@session_name_filter}
                session_scope={@session_scope}
                projects={@projects}
                session_project_visible={@session_project_visible}
                session_project_collapsed={@session_project_collapsed}
                sidebar_project={@sidebar_project}
                myself={@myself}
              />
            <% :tasks -> %>
              <TasksSection.tasks_content
                tasks={@flyout_tasks}
                task_search={@task_search}
                state_filter={@task_state_filter}
                sidebar_project={@sidebar_project}
                myself={@myself}
              />
            <% :prompts -> %>
              <PromptsSection.prompts_content
                prompts={@flyout_prompts}
                prompt_search={@prompt_search}
                prompt_scope={@prompt_scope}
                sidebar_project={@sidebar_project}
              />
            <% :chat -> %>
              <ChatSection.chat_content
                channels={@flyout_channels}
                active_channel_id={@active_channel_id}
                unread_counts={@unread_counts}
                myself={@myself}
              />
            <% :notes -> %>
              <NotesSection.notes_content
                notes={@flyout_notes}
                note_search={@note_search}
                note_parent_type={@note_parent_type}
                myself={@myself}
              />
            <% :skills -> %>
              <SkillsSection.skills_content
                skills={@flyout_skills}
                skills_route={Helpers.skills_route(@sidebar_project)}
              />
            <% :teams -> %>
              <TeamsSection.teams_content
                teams={@flyout_teams}
                team_search={@team_search}
                team_status={@team_status}
                sidebar_project={@sidebar_project}
              />
            <% :canvas -> %>
              <CanvasSection.canvas_content canvases={@flyout_canvases} />
            <% :agents -> %>
              <AgentsSection.agents_content agents={@flyout_agents} myself={@myself} />
            <% :notifications -> %>
              <Helpers.simple_link href="/notifications" label="Notifications" icon="hero-bell" />
            <% :usage -> %>
              <UsageSection.usage_content usage={@flyout_usage} />
            <% :jobs -> %>
              <JobsSection.jobs_content jobs={@flyout_jobs} sidebar_project={@sidebar_project} />
            <% :files -> %>
              <FilesSection.files_content
                file_nodes={@flyout_file_nodes}
                file_expanded={@flyout_file_expanded || MapSet.new()}
                file_children={@flyout_file_children}
                file_error={@flyout_file_error}
                sidebar_project={@sidebar_project}
                myself={@myself}
              />
            <% _ -> %>
              <TasksSection.nav_links project={@sidebar_project} section={:sessions} />
          <% end %>
        </div>
      </div>

      <%!-- ── Channel modal ── --%>
      <.new_channel_modal
        :if={@show_new_channel_form}
        myself={@myself}
      />

      <%!-- ── Rail modal (new task / new prompt) ── --%>
      <.rail_modal
        :if={@rail_modal in [:new_task, :new_prompt]}
        modal={@rail_modal}
        myself={@myself}
      />

      <%!-- ── Task detail modal ── --%>
      <.task_detail_modal
        :if={match?({:view_task, _, _}, @rail_modal)}
        task={Enum.at(elem(@rail_modal, 2), elem(@rail_modal, 1))}
        index={elem(@rail_modal, 1)}
        total={length(elem(@rail_modal, 2))}
        myself={@myself}
      />

      <%!-- ── Note detail modal ── --%>
      <.note_detail_modal
        :if={match?({:view_note, _, _}, @rail_modal)}
        note={Enum.at(elem(@rail_modal, 2), elem(@rail_modal, 1))}
        index={elem(@rail_modal, 1)}
        total={length(elem(@rail_modal, 2))}
        myself={@myself}
      />
    </div>
    """
  end

  # Shared + button used in headers
  attr :title, :string, required: true
  attr :rest, :global

  defp header_action_btn(assigns) do
    ~H"""
    <button
      title={@title}
      class="size-5 flex items-center justify-center rounded text-base-content/35 hover:text-base-content/70 hover:bg-base-content/8 transition-colors flex-shrink-0"
      {@rest}
    >
      <.icon name="hero-plus-mini" class="size-3.5" />
    </button>
    """
  end

  attr :modal, :atom, required: true
  attr :myself, :any, required: true

  defp rail_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-[100] flex items-center justify-center bg-black/40">
      <div class="bg-base-100 border border-base-content/10 rounded-lg shadow-xl w-72 p-4 flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <span class="text-sm font-semibold text-base-content/80">
            {if @modal == :new_task, do: "New Task", else: "New Prompt"}
          </span>
          <button
            type="button"
            phx-click="close_rail_modal"
            phx-target={@myself}
            class="size-5 flex items-center justify-center rounded text-base-content/40 hover:text-base-content/70 hover:bg-base-content/8 transition-colors"
          >
            <.icon name="hero-x-mark-mini" class="size-3.5" />
          </button>
        </div>

        <form phx-submit="submit_rail_modal" phx-target={@myself} class="flex flex-col gap-2">
          <input
            type="text"
            name="title"
            placeholder="Title"
            autofocus
            required
            class="w-full px-2.5 py-1.5 text-sm bg-base-content/5 border border-base-content/10 rounded focus:outline-none focus:border-primary/40 placeholder:text-base-content/30"
          />
          <textarea
            name="body"
            placeholder="Body (optional)"
            rows="3"
            class="w-full px-2.5 py-1.5 text-sm bg-base-content/5 border border-base-content/10 rounded focus:outline-none focus:border-primary/40 placeholder:text-base-content/30 resize-none"
          ></textarea>

          <div class="flex items-center justify-end gap-2">
            <button
              type="button"
              phx-click="close_rail_modal"
              phx-target={@myself}
              class="px-3 py-1 text-xs text-base-content/55 hover:text-base-content/80 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="px-3 py-1 text-xs bg-primary text-primary-content rounded hover:opacity-90 transition-opacity font-medium"
            >
              Create
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  attr :task, :map, required: true
  attr :index, :integer, required: true
  attr :total, :integer, required: true
  attr :myself, :any, required: true

  defp task_detail_modal(assigns) do
    task_link =
      if assigns.task && assigns.task.project_id do
        "/projects/#{assigns.task.project_id}/tasks?task_id=#{assigns.task.id}"
      else
        "/projects"
      end

    assigns = assign(assigns, :task_link, task_link)

    ~H"""
    <div class="fixed inset-0 z-[100] flex items-center justify-center bg-black/40">
      <div class="bg-base-100 border border-base-content/10 rounded-lg shadow-xl w-80 p-4 flex flex-col gap-3">
        <%!-- Header --%>
        <div class="flex items-start justify-between gap-2">
          <span class="text-sm font-semibold text-base-content/85 leading-snug">{@task.title}</span>
          <button
            type="button"
            phx-click="close_rail_modal"
            phx-target={@myself}
            class="size-5 flex-shrink-0 flex items-center justify-center rounded text-base-content/40 hover:text-base-content/70 hover:bg-base-content/8 transition-colors"
          >
            <.icon name="hero-x-mark-mini" class="size-3.5" />
          </button>
        </div>

        <%!-- State badge --%>
        <div class="flex items-center gap-2">
          <span class={["w-1.5 h-1.5 rounded-full flex-shrink-0", TasksSection.task_state_dot(@task.state_id)]} />
          <span class="text-xs text-base-content/55">{task_state_label(@task.state_id)}</span>
        </div>

        <%!-- Description --%>
        <%= if @task.description && @task.description != "" do %>
          <p class="text-xs text-base-content/60 leading-relaxed line-clamp-6">{@task.description}</p>
        <% end %>

        <%!-- Footer: prev/next + counter + open link --%>
        <div class="flex items-center justify-between pt-1 border-t border-base-content/8">
          <%!-- Prev / counter / Next --%>
          <div class="flex items-center gap-1">
            <button
              type="button"
              phx-click="task_detail_nav"
              phx-value-dir="prev"
              phx-target={@myself}
              disabled={@total <= 1}
              class="size-6 flex items-center justify-center rounded text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8 transition-colors disabled:opacity-25"
            >
              <.icon name="hero-chevron-left-mini" class="size-3.5" />
            </button>
            <span class="text-nano text-base-content/35 tabular-nums">
              {@index + 1}/{@total}
            </span>
            <button
              type="button"
              phx-click="task_detail_nav"
              phx-value-dir="next"
              phx-target={@myself}
              disabled={@total <= 1}
              class="size-6 flex items-center justify-center rounded text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8 transition-colors disabled:opacity-25"
            >
              <.icon name="hero-chevron-right-mini" class="size-3.5" />
            </button>
          </div>

          <%!-- Open link --%>
          <.link
            navigate={@task_link}
            class="px-3 py-1 text-xs bg-primary text-primary-content rounded hover:opacity-90 transition-opacity font-medium"
          >
            Open task →
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp task_state_label(1), do: "To Do"
  defp task_state_label(2), do: "In Progress"
  defp task_state_label(3), do: "Done"
  defp task_state_label(4), do: "In Review"
  defp task_state_label(_), do: "Unknown"

  attr :note, :map, required: true
  attr :index, :integer, required: true
  attr :total, :integer, required: true
  attr :myself, :any, required: true

  defp note_detail_modal(assigns) do
    edit_link = "/notes/#{assigns.note.id}/edit"
    assigns = assign(assigns, :edit_link, edit_link)

    ~H"""
    <div class="fixed inset-0 z-[100] flex items-center justify-center bg-black/40">
      <div class="bg-base-100 border border-base-content/10 rounded-lg shadow-xl w-80 p-4 flex flex-col gap-3">
        <%!-- Header --%>
        <div class="flex items-start justify-between gap-2">
          <div class="min-w-0 flex-1">
            <span class="text-sm font-semibold text-base-content/85 leading-snug block truncate">
              {note_label(@note)}
            </span>
            <span class="text-micro text-base-content/30 uppercase tracking-wide">
              {@note.parent_type}
            </span>
          </div>
          <button
            type="button"
            phx-click="close_rail_modal"
            phx-target={@myself}
            class="size-5 flex-shrink-0 flex items-center justify-center rounded text-base-content/40 hover:text-base-content/70 hover:bg-base-content/8 transition-colors"
          >
            <.icon name="hero-x-mark-mini" class="size-3.5" />
          </button>
        </div>

        <%!-- Body --%>
        <%= if @note.body && @note.body != "" do %>
          <p class="text-xs text-base-content/60 leading-relaxed max-h-48 overflow-y-auto whitespace-pre-wrap break-words">
            {@note.body}
          </p>
        <% end %>

        <%!-- Footer: prev/next + counter + edit link --%>
        <div class="flex items-center justify-between pt-1 border-t border-base-content/8">
          <div class="flex items-center gap-1">
            <button
              type="button"
              phx-click="note_detail_nav"
              phx-value-dir="prev"
              phx-target={@myself}
              disabled={@total <= 1}
              class="size-6 flex items-center justify-center rounded text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8 transition-colors disabled:opacity-25"
            >
              <.icon name="hero-chevron-left-mini" class="size-3.5" />
            </button>
            <span class="text-nano text-base-content/35 tabular-nums">
              {@index + 1}/{@total}
            </span>
            <button
              type="button"
              phx-click="note_detail_nav"
              phx-value-dir="next"
              phx-target={@myself}
              disabled={@total <= 1}
              class="size-6 flex items-center justify-center rounded text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8 transition-colors disabled:opacity-25"
            >
              <.icon name="hero-chevron-right-mini" class="size-3.5" />
            </button>
          </div>

          <.link
            navigate={@edit_link}
            class="px-3 py-1 text-xs bg-primary text-primary-content rounded hover:opacity-90 transition-opacity font-medium"
          >
            Edit note →
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp note_label(note) do
    label = note.title || String.slice(note.body || "", 0, 60)
    if label == "", do: "(empty)", else: label
  end

  attr :myself, :any, required: true

  defp new_channel_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-[100] flex items-center justify-center bg-black/40">
      <div class="bg-base-100 border border-base-content/10 rounded-lg shadow-xl w-72 p-4 flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <span class="text-sm font-semibold text-base-content/80">New Channel</span>
          <button
            type="button"
            phx-click="toggle_new_channel_form"
            phx-target={@myself}
            class="size-5 flex items-center justify-center rounded text-base-content/40 hover:text-base-content/70 hover:bg-base-content/8 transition-colors"
          >
            <.icon name="hero-x-mark-mini" class="size-3.5" />
          </button>
        </div>

        <form phx-submit="create_channel" phx-target={@myself} class="flex flex-col gap-2">
          <div>
            <input
              type="text"
              name="channel_name"
              placeholder="Channel name"
              autofocus
              required
              class="w-full px-2.5 py-1.5 text-sm bg-base-content/5 border border-base-content/10 rounded focus:outline-none focus:border-primary/40 placeholder:text-base-content/30"
            />
            <div class="text-xs text-base-content/40 mt-1">
              Use lowercase letters, numbers, and hyphens
            </div>
          </div>

          <div class="flex items-center justify-end gap-2">
            <button
              type="button"
              phx-click="toggle_new_channel_form"
              phx-target={@myself}
              class="px-3 py-1 text-xs text-base-content/55 hover:text-base-content/80 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="px-3 py-1 text-xs bg-primary text-primary-content rounded hover:opacity-90 transition-opacity font-medium"
            >
              Create
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
