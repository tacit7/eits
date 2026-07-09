defmodule EyeInTheSkyWeb.Components.JobsTable do
  @moduledoc """
  Jobs list component — renders a divide-y list of job rows matching the
  sessions/notes/skills visual style, with a spinner or status dot on the
  left, name + inline tags, schedule/run metadata, and hover-revealed
  run-now / edit / delete actions.
  """

  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  import EyeInTheSkyWeb.Live.Shared.JobsFormatters,
    only: [job_row_state: 3, format_schedule: 1, type_label: 1]

  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [format_relative_time: 1]

  attr :jobs, :list, required: true
  attr :expanded_job_id, :any, required: true
  attr :runs, :list, required: true
  attr :running_ids, :any, required: true
  attr :last_run_map, :map, required: true
  attr :last_failed_runs, :map, required: true
  attr :show_origin, :boolean, default: false
  attr :target, :any, default: nil
  attr :scope, :string, default: nil
  attr :project_name, :string, default: nil
  attr :bulk_selected_jobs, :any, default: nil
  attr :last_n_runs_map, :map, default: %{}

  def jobs_table(assigns) do
    ~H"""
    <%= if @jobs != [] do %>
      <div class="mt-2 rounded-xl shadow-sm overflow-hidden">
        <div class="divide-y divide-base-content/5">
        <%= for job <- @jobs do %>
          <% job_state = job_row_state(job, @running_ids, @last_run_map) %>
          <% selected? = @expanded_job_id == job.id %>
          <div
            id={"job-row-#{job.id}"}
            class={[
              "flex items-center gap-3 py-3 px-4 cursor-pointer relative group/row bg-base-100",
              "[&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50 [&.vim-nav-focused]:ring-inset",
              if(selected?, do: "bg-primary/5 ring-1 ring-primary/20 ring-inset", else: "hover:bg-base-200/40"),
              if(job_state == :disabled, do: "opacity-60")
            ]}
            phx-click="expand_job"
            phx-value-id={job.id}
            phx-target={@target}
            role="button"
            tabindex="0"
            aria-label={job.name}
          >
            <%!-- Status icon: spinner when running, coloured dot otherwise --%>
            <%= if job_state == :running do %>
              <span class="loading loading-spinner loading-xs text-primary flex-shrink-0" />
            <% else %>
              <span class={[
                "size-2 rounded-full flex-shrink-0",
                case job_state do
                  :healthy -> "bg-success"
                  :failed -> "bg-error"
                  _ -> "bg-base-content/20"
                end
              ]} />
            <% end %>

            <%!-- Main content --%>
            <div class="flex-1 min-w-0">
              <%!-- Line 1: name + type badge --%>
              <div class="flex items-center gap-2">
                <span class={[
                  "text-sm font-semibold truncate",
                  if(selected?, do: "text-primary", else: "text-base-content/85")
                ]}>
                  {job.name}
                </span>
                <span class="text-mini font-medium px-1.5 py-0.5 rounded bg-base-content/8 text-base-content/45 flex-shrink-0">
                  {type_label(job.job_type)}
                </span>
                <%= if is_nil(job.project_id) and @scope == "overview" do %>
                  <span class="text-mini font-medium px-1.5 py-0.5 rounded bg-base-content/6 text-base-content/35 flex-shrink-0">global</span>
                <% end %>
                <%= if @show_origin and job.origin == "system" do %>
                  <span class="text-mini font-medium px-1.5 py-0.5 rounded bg-base-content/6 text-base-content/35 flex-shrink-0">system</span>
                <% end %>
              </div>
              <%!-- Line 2: schedule · last run · next run --%>
              <div class="flex items-center gap-1.5 mt-0.5 text-mini text-base-content/40 font-mono">
                <span>{format_schedule(job)}</span>
                <span class="text-base-content/20">·</span>
                <%= if job.last_run_at do %>
                  <span class={if job_state == :failed, do: "text-error/60"}>
                    Last run {format_relative_time(job.last_run_at)}
                  </span>
                <% else %>
                  <span class="text-base-content/25">Never run</span>
                <% end %>
                <%= if not is_nil(job.next_run_at) and job_state != :disabled do %>
                  <span class="text-base-content/20">·</span>
                  <span>Next {format_relative_time(job.next_run_at)}</span>
                <% end %>
              </div>
            </div>

            <%!-- Status badge --%>
            <%= if job_state == :running do %>
              <span class="text-mini font-medium px-1.5 py-0.5 rounded bg-primary/15 text-primary flex-shrink-0">running</span>
            <% end %>
            <%= if job_state == :disabled do %>
              <span class="text-mini font-medium px-1.5 py-0.5 rounded bg-base-content/8 text-base-content/40 flex-shrink-0">disabled</span>
            <% end %>
            <%= if job_state == :failed do %>
              <span class="text-mini font-medium px-1.5 py-0.5 rounded bg-error/15 text-error flex-shrink-0">failed</span>
            <% end %>

              <%!-- Hover-reveal actions.
                   phx-click="noop" on wrapper intercepts click so the row's
                   expand_job does not also fire when targeting an action button. --%>
              <div
                class="flex items-center gap-0 flex-shrink-0 opacity-0 group-hover/row:opacity-100 transition-opacity duration-100"
                phx-click="noop"
                phx-target={@target}
              >
                <button
                  class="flex items-center justify-center size-8 rounded text-base-content/40 hover:text-base-content/80 hover:bg-base-200/70 transition-colors"
                  phx-click="run_now"
                  phx-value-id={job.id}
                  phx-target={@target}
                  title="Run now"
                  aria-label="Run job now"
                >
                  <.icon name="hero-play" class="size-3.5" />
                </button>
                <%= if job.origin != "system" do %>
                  <button
                    class="flex items-center justify-center size-8 rounded text-base-content/40 hover:text-base-content/80 hover:bg-base-200/70 transition-colors"
                    phx-click="edit_job"
                    phx-value-id={job.id}
                    phx-target={@target}
                    title="Edit"
                    aria-label="Edit job"
                  >
                    <.icon name="hero-pencil-square" class="size-3.5" />
                  </button>
                  <button
                    class="flex items-center justify-center size-8 rounded text-error/40 hover:text-error hover:bg-error/10 transition-colors"
                    phx-click="delete_job"
                    phx-value-id={job.id}
                    phx-target={@target}
                    data-confirm="Delete this job?"
                    title="Delete"
                    aria-label="Delete job"
                  >
                    <.icon name="hero-trash" class="size-3.5" />
                  </button>
                <% end %>
            </div>
          </div>
        <% end %>
        </div>
      </div>
    <% else %>
      <.empty_state
        id={"jobs-empty-#{@scope || "all"}"}
        icon="hero-clock"
        title="No jobs yet"
        subtitle={
          if @scope == "project",
            do: "Create a job to automate work in this project",
            else: "Create jobs to automate recurring work on a schedule"
        }
      />
    <% end %>
    """
  end
end
