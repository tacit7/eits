defmodule EyeInTheSkyWeb.Components.JobsTable do
  @moduledoc """
  Shared jobs table component — renders both mobile cards and a desktop table.

  Attributes:
    - jobs: list of ScheduledJob structs (required)
    - expanded_job_id: integer or nil (required)
    - runs: list of JobRun structs (required)
    - running_ids: MapSet of job IDs currently executing (required)
    - last_run_map: %{job_id => status_string} (required)
    - last_failed_runs: %{job_id => %JobRun{}} (required)
    - show_origin: boolean — adds an Origin column to the desktop table (default false)
  """

  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents
  import EyeInTheSkyWeb.Live.Shared.JobsFormatters,
    only: [
      job_row_state: 3,
      row_border_class: 1,
      format_schedule: 1,
      type_label: 1,
      status_badge_class: 1
    ]

  import EyeInTheSkyWeb.Helpers.ViewHelpers,
    only: [format_relative_time: 1, format_datetime_short_time: 1]

  attr :jobs, :list, required: true
  attr :expanded_job_id, :any, required: true
  attr :runs, :list, required: true
  attr :running_ids, :any, required: true
  attr :last_run_map, :map, required: true
  attr :last_failed_runs, :map, required: true
  attr :show_origin, :boolean, default: false

  def jobs_table(assigns) do
    ~H"""
    <%= if length(@jobs) > 0 do %>
      <div class="md:hidden space-y-3">
        <%= for job <- @jobs do %>
          <% job_state = job_row_state(job, @running_ids, @last_run_map) %>
          <article class={"rounded-xl border border-base-content/10 bg-base-100 p-3 shadow-sm #{row_border_class(job_state)}"}>
            <button class="w-full text-left" phx-click="expand_job" phx-value-id={job.id}>
              <div class="flex items-start justify-between gap-2">
                <div class="min-w-0">
                  <div class="flex items-center gap-1.5">
                    <h3 class="font-medium text-sm truncate">{job.name}</h3>
                    <%= if job_state == :running do %>
                      <span class="badge badge-warning badge-xs animate-pulse shrink-0">running</span>
                    <% end %>
                  </div>
                  <%= if job.description do %>
                    <p class="text-[11px] text-base-content/60 mt-0.5 truncate">{job.description}</p>
                  <% end %>
                  <p class="text-[11px] font-mono text-base-content/50 mt-1 truncate">
                    {format_schedule(job)}
                    <span class="text-base-content/30 not-italic ml-1">{job.timezone || "UTC"}</span>
                  </p>
                </div>
                <span class="badge badge-xs badge-ghost">
                  {type_label(job.job_type)}
                </span>
              </div>
            </button>

            <% mobile_failed_run = Map.get(@last_failed_runs, job.id) %>
            <%= if mobile_failed_run do %>
              <div class="flex items-center gap-1.5 mt-2 flex-wrap">
                <span class="badge badge-xs badge-error">failed</span>
                <span class="text-xs text-error/70 truncate flex-1">
                  {format_relative_time(mobile_failed_run.started_at)}{if mobile_failed_run.result,
                    do: ": #{String.slice(mobile_failed_run.result, 0, 60)}",
                    else: ""}
                </span>
                <button
                  class="btn btn-ghost btn-xs text-error shrink-0"
                  phx-click="run_now"
                  phx-value-id={job.id}
                  title="Retry"
                >
                  <.icon name="hero-arrow-path" class="w-3 h-3" />
                </button>
              </div>
            <% end %>

            <div class="mt-3 flex items-center justify-between">
              <span class="text-xs text-base-content/60">Enabled</span>
              <span class={[
                "badge badge-xs",
                if(job.enabled == 1, do: "badge-success", else: "badge-ghost")
              ]}>
                {if job.enabled == 1, do: "Yes", else: "No"}
              </span>
            </div>

            <div class="mt-3 grid grid-cols-2 gap-x-2 gap-y-1 text-xs">
              <span class="text-base-content/50">Last Run</span>
              <span class="text-right" title={format_datetime_short_time(job.last_run_at)}>
                {format_relative_time(job.last_run_at)}
              </span>
              <span class="text-base-content/50">Next Run</span>
              <span class="text-right" title={format_datetime_short_time(job.next_run_at)}>
                {format_relative_time(job.next_run_at)}
              </span>
              <span class="text-base-content/50">Runs</span>
              <span class="text-right">{job.run_count || 0}</span>
            </div>

            <div class="mt-3 flex items-center justify-end gap-1 border-t border-base-content/10 pt-2">
              <input
                type="checkbox"
                class="toggle toggle-xs toggle-primary"
                checked={job.enabled == 1}
                phx-click="toggle_job"
                phx-value-id={job.id}
              />
              <button
                class="btn btn-ghost btn-xs"
                phx-click="run_now"
                phx-value-id={job.id}
                title="Run Now"
              >
                <.icon name="hero-play" class="w-3 h-3" />
              </button>
              <button
                class="btn btn-ghost btn-xs"
                phx-click="edit_job"
                phx-value-id={job.id}
                title="Edit"
              >
                <.icon name="hero-pencil-square" class="w-3 h-3" />
              </button>
              <button
                class="btn btn-ghost btn-xs text-error"
                phx-click="delete_job"
                phx-value-id={job.id}
                data-confirm="Delete this job?"
                title="Delete"
              >
                <.icon name="hero-trash" class="w-3 h-3" />
              </button>
            </div>

            <%= if @expanded_job_id == job.id do %>
              <div class="mt-3 rounded-lg bg-base-200/50 p-2">
                <p class="text-xs font-medium mb-2">Recent Runs</p>
                <%= if length(@runs) > 0 do %>
                  <div class="space-y-1.5">
                    <%= for run <- @runs do %>
                      <div class="rounded-md bg-base-100/70 p-2 text-xs">
                        <div class="flex items-center justify-between gap-2">
                          <span class={"badge badge-xs #{status_badge_class(run.status)}"}>
                            {run.status}
                          </span>
                          <span class="text-base-content/60 truncate">
                            {format_datetime_short_time(run.started_at)}
                          </span>
                        </div>
                        <p class="mt-1 text-base-content/60 truncate">{run.result || "-"}</p>
                      </div>
                    <% end %>
                  </div>
                <% else %>
                  <p class="text-xs text-base-content/50">No runs yet</p>
                <% end %>
              </div>
            <% end %>
          </article>
        <% end %>
      </div>

      <div class="hidden md:block -mx-4 sm:mx-0 overflow-x-auto px-4 sm:px-0">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Name</th>
              <%= if @show_origin do %>
                <th>Origin</th>
              <% end %>
              <th>Type</th>
              <th>Schedule</th>
              <th>Enabled</th>
              <th>Last Run</th>
              <th>Next Run</th>
              <th>Runs</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <%= for job <- @jobs do %>
              <% row_state = job_row_state(job, @running_ids, @last_run_map) %>
              <tr class={"hover #{if @expanded_job_id == job.id, do: "bg-base-200"}"}>
                <td
                  class={"cursor-pointer #{row_border_class(row_state)}"}
                  phx-click="expand_job"
                  phx-value-id={job.id}
                >
                  <div class="flex items-center gap-1.5">
                    <div class="font-medium">{job.name}</div>
                    <%= if row_state == :running do %>
                      <span class="badge badge-warning badge-xs animate-pulse">running</span>
                    <% end %>
                  </div>
                  <%= if job.description do %>
                    <p class="text-xs text-base-content/50 mt-0.5">{job.description}</p>
                  <% end %>
                  <%= if job.origin == "system" do %>
                    <span class="badge badge-xs badge-ghost">system</span>
                  <% end %>
                  <% failed_run = Map.get(@last_failed_runs, job.id) %>
                  <%= if failed_run do %>
                    <div class="flex items-center gap-1.5 mt-1.5 flex-wrap">
                      <span class="badge badge-xs badge-error">failed</span>
                      <span class="text-xs text-error/70">
                        {format_relative_time(failed_run.started_at)}{if failed_run.result,
                          do: ": #{String.slice(failed_run.result, 0, 60)}",
                          else: ""}
                      </span>
                      <button
                        class="btn btn-ghost btn-xs text-error"
                        phx-click="run_now"
                        phx-value-id={job.id}
                        title="Retry"
                      >
                        <.icon name="hero-arrow-path" class="w-3 h-3" />
                      </button>
                    </div>
                  <% end %>
                </td>
                <%= if @show_origin do %>
                  <td>
                    <%= if job.origin == "system" do %>
                      <span class="badge badge-xs badge-neutral">System</span>
                    <% else %>
                      <span class="badge badge-xs badge-ghost">User</span>
                    <% end %>
                  </td>
                <% end %>
                <td>
                  <span class="badge badge-xs badge-ghost">
                    {type_label(job.job_type)}
                  </span>
                </td>
                <td class="text-xs">
                  <span class="font-mono">{format_schedule(job)}</span>
                  <span class="text-base-content/40 ml-1 text-xs">{job.timezone || "UTC"}</span>
                </td>
                <td>
                  <input
                    type="checkbox"
                    class="toggle toggle-sm toggle-primary"
                    checked={job.enabled == 1}
                    phx-click="toggle_job"
                    phx-value-id={job.id}
                  />
                </td>
                <td class="text-xs" title={format_datetime_short_time(job.last_run_at)}>
                  {format_relative_time(job.last_run_at)}
                </td>
                <td class="text-xs" title={format_datetime_short_time(job.next_run_at)}>
                  {format_relative_time(job.next_run_at)}
                </td>
                <td class="text-xs">{job.run_count || 0}</td>
                <td>
                  <div class="flex items-center gap-1">
                    <button
                      class="btn btn-ghost btn-xs"
                      phx-click="run_now"
                      phx-value-id={job.id}
                      title="Run Now"
                      aria-label="Run job now"
                    >
                      <.icon name="hero-play" class="w-3.5 h-3.5" />
                    </button>
                    <%= if job.origin != "system" do %>
                      <button
                        class="btn btn-ghost btn-xs"
                        phx-click="edit_job"
                        phx-value-id={job.id}
                        title="Edit"
                        aria-label="Edit job"
                      >
                        <.icon name="hero-pencil-square" class="w-3.5 h-3.5" />
                      </button>
                      <button
                        class="btn btn-ghost btn-xs text-error"
                        phx-click="delete_job"
                        phx-value-id={job.id}
                        data-confirm="Delete this job?"
                        title="Delete"
                        aria-label="Delete job"
                      >
                        <.icon name="hero-trash" class="w-3.5 h-3.5" />
                      </button>
                    <% end %>
                  </div>
                </td>
              </tr>
              <%= if @expanded_job_id == job.id do %>
                <tr>
                  <td colspan={if @show_origin, do: "9", else: "8"} class="bg-base-200 p-4">
                    <div class="text-sm font-medium mb-2">Recent Runs</div>
                    <%= if length(@runs) > 0 do %>
                      <table class="table table-xs">
                        <thead>
                          <tr>
                            <th>Status</th>
                            <th>Started</th>
                            <th>Completed</th>
                            <th>Result</th>
                          </tr>
                        </thead>
                        <tbody>
                          <%= for run <- @runs do %>
                            <tr>
                              <td>
                                <span class={"badge badge-xs #{status_badge_class(run.status)}"}>
                                  {run.status}
                                </span>
                              </td>
                              <td class="text-xs">{format_datetime_short_time(run.started_at)}</td>
                              <td class="text-xs">{format_datetime_short_time(run.completed_at)}</td>
                              <td class="text-xs max-w-xs truncate" title={run.result || ""}>
                                {String.slice(run.result || "-", 0, 120)}
                              </td>
                            </tr>
                          <% end %>
                        </tbody>
                      </table>
                    <% else %>
                      <p class="text-xs text-base-content/50">No runs yet</p>
                    <% end %>
                  </td>
                </tr>
              <% end %>
            <% end %>
          </tbody>
        </table>
      </div>
    <% else %>
      <div class="text-center py-8 rounded-lg border border-base-300">
        <.icon name="hero-calendar" class="w-6 h-6 text-base-content/30 mx-auto mb-2" />
        <p class="text-sm text-base-content/50">No scheduled jobs</p>
      </div>
    <% end %>
    """
  end
end
