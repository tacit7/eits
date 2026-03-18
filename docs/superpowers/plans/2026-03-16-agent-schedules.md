# Agent Schedules Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an "Agent Schedules" tab to the Jobs LiveView that lets users schedule saved prompt templates (`subagent_prompts`) to run as `spawn_agent` cron jobs.

**Architecture:** Add `prompt_id` FK column to `scheduled_jobs`, expose three new context functions, add a new scheduling form component (drawer on mobile / modal on desktop via CSS), and wire up two LiveViews with six new event handlers delegated through a new shared helper module.

**Tech Stack:** Elixir/Phoenix LiveView, Ecto, PostgreSQL, Tailwind CSS + DaisyUI, Oban

**Spec:** `docs/superpowers/specs/2026-03-16-agent-schedules-design.md`

---

## File Map

### New files
| File | Responsibility |
|---|---|
| `priv/repo/migrations/TIMESTAMP_add_prompt_id_to_scheduled_jobs.exs` | Add `prompt_id` FK column + indexes |
| `lib/eye_in_the_sky_web_web/components/agent_schedule_form.ex` | Scheduling form component (drawer + modal, same template) |
| `lib/eye_in_the_sky_web_web/live/shared/agent_schedule_helpers.ex` | Shared event handlers for agent schedule events |

### Modified files
| File | What changes |
|---|---|
| `lib/eye_in_the_sky_web/scheduled_jobs/scheduled_job.ex` | Add `prompt_id` field, `belongs_to`, `unique_constraint` |
| `lib/eye_in_the_sky_web/scheduled_jobs.ex` | Add `list_spawn_agent_jobs_by_prompt_ids/1`, `list_orphaned_agent_jobs/0`, update `create_job/1` error handling |
| `lib/eye_in_the_sky_web/prompts.ex` | Update `delete_prompt/1` to rescue `Ecto.ConstraintError` (FK violation) |
| `lib/eye_in_the_sky_web_web/live/overview_live/jobs.ex` | Add new assigns on mount, tab + schedule event handlers, update `handle_info`, update `render` |
| `lib/eye_in_the_sky_web_web/live/project_live/jobs.ex` | Same as overview — new assigns, event handlers, render |

### Test files
| File | What changes |
|---|---|
| `test/eye_in_the_sky_web/scheduled_jobs_test.exs` | Tests for new context functions + `prompt_id` uniqueness |
| `test/eye_in_the_sky_web/prompts_test.exs` | Test FK error on `delete_prompt/1` with active schedule |

---

## Chunk 1: Data Layer

Migration, schema, and context functions.

### Task 1: Generate and write the migration

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_add_prompt_id_to_scheduled_jobs.exs`

- [ ] **Step 1: Generate the migration file**

```bash
mix ecto.gen.migration add_prompt_id_to_scheduled_jobs
```

Note the generated filename (timestamp prefix). Open the file.

- [ ] **Step 2: Write the migration body**

```elixir
defmodule EyeInTheSkyWeb.Repo.Migrations.AddPromptIdToScheduledJobs do
  use Ecto.Migration

  def up do
    alter table(:scheduled_jobs) do
      add :prompt_id, references(:subagent_prompts, on_delete: :restrict), null: true
    end

    create index(:scheduled_jobs, [:prompt_id])

    create unique_index(:scheduled_jobs, [:prompt_id],
      where: "prompt_id IS NOT NULL",
      name: :idx_scheduled_jobs_unique_prompt
    )
  end

  def down do
    drop_if_exists index(:scheduled_jobs, [:prompt_id])
    drop_if_exists unique_index(:scheduled_jobs, [:prompt_id], name: :idx_scheduled_jobs_unique_prompt)

    alter table(:scheduled_jobs) do
      remove :prompt_id
    end
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
mix ecto.migrate
```

Expected: `== Running ... AddPromptIdToScheduledJobs` with no errors.

- [ ] **Step 4: Verify column exists**

```bash
psql -d eits_dev -c "\d scheduled_jobs" | grep prompt_id
```

Expected: `prompt_id | bigint | | |`

---

### Task 2: Update `ScheduledJob` schema

**Files:**
- Modify: `lib/eye_in_the_sky_web/scheduled_jobs/scheduled_job.ex`

- [ ] **Step 1: Write failing tests**

In `test/eye_in_the_sky_web/scheduled_jobs_test.exs`, add:

```elixir
describe "ScheduledJob schema" do
  test "cast includes prompt_id" do
    attrs = %{
      "name" => "Test",
      "job_type" => "spawn_agent",
      "schedule_type" => "cron",
      "schedule_value" => "0 5 * * *",
      "prompt_id" => 999
    }
    cs = ScheduledJob.changeset(%ScheduledJob{}, attrs)
    assert cs.changes.prompt_id == 999
  end

  test "prompt_id uniqueness constraint is registered" do
    cs = ScheduledJob.changeset(%ScheduledJob{}, %{})
    constraint_names = Enum.map(cs.constraints, & &1.constraint)
    assert "idx_scheduled_jobs_unique_prompt" in constraint_names
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
mix test test/eye_in_the_sky_web/scheduled_jobs_test.exs 2>&1 | tail -15
```

Expected: 2 failures.

- [ ] **Step 3: Update the schema**

In `lib/eye_in_the_sky_web/scheduled_jobs/scheduled_job.ex`, update `schema` and `changeset/2`:

```elixir
schema "scheduled_jobs" do
  field :name, :string
  field :description, :string
  field :job_type, :string
  field :origin, :string, default: "user"
  field :schedule_type, :string
  field :schedule_value, :string
  field :config, :string, default: "{}"
  field :enabled, :integer, default: 1
  field :last_run_at, :string
  field :next_run_at, :string
  field :run_count, :integer, default: 0
  field :created_at, :string
  field :updated_at, :string
  field :project_id, :integer
  field :prompt_id, :id  # :id = bigint, matches subagent_prompts PK

  has_many :runs, EyeInTheSkyWeb.ScheduledJobs.JobRun, foreign_key: :job_id
  belongs_to :prompt, EyeInTheSkyWeb.Prompts.Prompt,
    foreign_key: :prompt_id,
    references: :id,
    define_field: false
end

def changeset(job, attrs) do
  job
  |> cast(attrs, [
    :name, :description, :job_type, :origin, :schedule_type,
    :schedule_value, :config, :enabled, :last_run_at, :next_run_at,
    :run_count, :created_at, :updated_at, :project_id,
    :prompt_id  # <-- new
  ])
  |> validate_required([:name, :job_type, :schedule_type, :schedule_value])
  |> validate_inclusion(:job_type, ["spawn_agent", "shell_command", "mix_task", "daily_digest"])
  |> validate_inclusion(:origin, ["system", "user"])
  |> validate_inclusion(:schedule_type, ["interval", "cron"])
  |> unique_constraint(:prompt_id, name: :idx_scheduled_jobs_unique_prompt)  # <-- new
end
```

- [ ] **Step 4: Run tests to confirm pass**

```bash
mix test test/eye_in_the_sky_web/scheduled_jobs_test.exs 2>&1 | tail -10
```

Expected: 0 failures.

- [ ] **Step 5: Compile check**

```bash
mix compile 2>&1 | grep "error:" | head -10
```

Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add priv/repo/migrations/ lib/eye_in_the_sky_web/scheduled_jobs/scheduled_job.ex test/eye_in_the_sky_web/scheduled_jobs_test.exs
git commit -m "feat: add prompt_id to scheduled_jobs schema with FK, unique index, belongs_to"
```

---

### Task 3: Add new context functions to `ScheduledJobs`

**Files:**
- Modify: `lib/eye_in_the_sky_web/scheduled_jobs.ex`

- [ ] **Step 1: Write failing tests**

In `test/eye_in_the_sky_web/scheduled_jobs_test.exs`, add a prompt helper and new describe blocks:

```elixir
# Add near top of file alongside existing helpers
alias EyeInTheSkyWeb.Prompts

defp create_prompt(name \\ "Test Prompt") do
  {:ok, p} = Prompts.create_prompt(%{
    name: name,
    slug: "#{System.unique_integer([:positive])}-#{String.downcase(String.replace(name, " ", "-"))}",
    prompt_text: "Do the thing",
    active: true
  })
  p
end

defp spawn_agent_attrs(overrides \\ %{}) do
  Map.merge(%{
    "name" => "Test Agent Job",
    "job_type" => "spawn_agent",
    "schedule_type" => "cron",
    "schedule_value" => "0 5 * * *"
  }, overrides)
end
```

```elixir
describe "list_spawn_agent_jobs_by_prompt_ids/1" do
  test "returns jobs matching given prompt_ids" do
    prompt = create_prompt()
    {:ok, job} = ScheduledJobs.create_job(spawn_agent_attrs(%{"prompt_id" => prompt.id}))
    results = ScheduledJobs.list_spawn_agent_jobs_by_prompt_ids([prompt.id])
    assert Enum.any?(results, &(&1.id == job.id))
  end

  test "returns empty list for unknown ids" do
    assert ScheduledJobs.list_spawn_agent_jobs_by_prompt_ids([999_999]) == []
  end
end

describe "list_orphaned_agent_jobs/0" do
  test "returns spawn_agent jobs whose prompt is inactive" do
    prompt = create_prompt("Inactive")
    {:ok, job} = ScheduledJobs.create_job(spawn_agent_attrs(%{"prompt_id" => prompt.id}))
    {:ok, _} = Prompts.update_prompt(prompt, %{active: false})
    orphans = ScheduledJobs.list_orphaned_agent_jobs()
    assert Enum.any?(orphans, &(&1.id == job.id))
  end

  test "does not return jobs whose prompt is active" do
    prompt = create_prompt("Active")
    {:ok, job} = ScheduledJobs.create_job(spawn_agent_attrs(%{"prompt_id" => prompt.id}))
    orphans = ScheduledJobs.list_orphaned_agent_jobs()
    refute Enum.any?(orphans, &(&1.id == job.id))
  end
end

describe "create_job/1 duplicate prompt_id" do
  test "returns {:error, :already_scheduled}" do
    prompt = create_prompt("Dupe")
    {:ok, _} = ScheduledJobs.create_job(spawn_agent_attrs(%{"prompt_id" => prompt.id, "name" => "First"}))
    result = ScheduledJobs.create_job(spawn_agent_attrs(%{"prompt_id" => prompt.id, "name" => "Second"}))
    assert result == {:error, :already_scheduled}
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
mix test test/eye_in_the_sky_web/scheduled_jobs_test.exs 2>&1 | tail -15
```

Expected: failures for undefined functions.

- [ ] **Step 3: Add new functions to `scheduled_jobs.ex`**

After `list_global_jobs/0`:

```elixir
def list_spawn_agent_jobs_by_prompt_ids(prompt_ids) when is_list(prompt_ids) do
  from(j in ScheduledJob, where: j.prompt_id in ^prompt_ids)
  |> Repo.all()
end

def list_orphaned_agent_jobs do
  from(j in ScheduledJob,
    join: p in assoc(j, :prompt),
    where: j.job_type == "spawn_agent",
    where: not is_nil(j.prompt_id),
    where: p.active == false
  )
  |> Repo.all()
end
```

- [ ] **Step 4: Update `create_job/1` error handling**

Find the `case Repo.insert(changeset) do` in `create_job/1`. Replace the error clause:

```elixir
{:error, %Ecto.Changeset{} = cs} ->
  if Keyword.has_key?(cs.errors, :prompt_id),
    do: {:error, :already_scheduled},
    else: {:error, cs}
```

- [ ] **Step 5: Run tests**

```bash
mix test test/eye_in_the_sky_web/scheduled_jobs_test.exs 2>&1 | tail -10
```

Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add lib/eye_in_the_sky_web/scheduled_jobs.ex test/eye_in_the_sky_web/scheduled_jobs_test.exs
git commit -m "feat: add list_spawn_agent_jobs_by_prompt_ids, list_orphaned_agent_jobs, duplicate guard"
```

---

## Chunk 2: Prompt Deletion Guard

### Task 4: Guard `delete_prompt/1` against FK violation

**Files:**
- Modify: `lib/eye_in_the_sky_web/prompts.ex`

- [ ] **Step 1: Write failing test**

In `test/eye_in_the_sky_web/prompts_test.exs` (create if missing):

```elixir
defmodule EyeInTheSkyWeb.PromptsTest do
  use EyeInTheSkyWeb.DataCase, async: true

  alias EyeInTheSkyWeb.{Prompts, ScheduledJobs}

  defp create_prompt(name \\ "Test") do
    {:ok, p} = Prompts.create_prompt(%{
      name: name,
      slug: "#{System.unique_integer([:positive])}-test",
      prompt_text: "Do something",
      active: true
    })
    p
  end

  describe "delete_prompt/1" do
    test "succeeds when no schedule exists" do
      prompt = create_prompt()
      assert {:ok, _} = Prompts.delete_prompt(prompt)
    end

    test "returns {:error, :has_active_schedule} when a schedule exists" do
      prompt = create_prompt("Scheduled")
      {:ok, _} = ScheduledJobs.create_job(%{
        "name" => "Guard Test",
        "job_type" => "spawn_agent",
        "schedule_type" => "cron",
        "schedule_value" => "0 5 * * *",
        "prompt_id" => prompt.id
      })
      assert Prompts.delete_prompt(prompt) == {:error, :has_active_schedule}
    end
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
mix test test/eye_in_the_sky_web/prompts_test.exs 2>&1 | tail -15
```

Expected: second test fails (raises or returns wrong error).

- [ ] **Step 3: Update `delete_prompt/1` in `prompts.ex`**

`Repo.delete/1` raises `Ecto.ConstraintError` when a FK constraint fires and the constraint isn't registered on the Prompt changeset. Use `rescue` to catch it:

```elixir
def delete_prompt(%Prompt{} = prompt) do
  case Repo.delete(prompt) do
    {:ok, p} -> {:ok, p}
    {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
  end
rescue
  Ecto.ConstraintError -> {:error, :has_active_schedule}
end
```

- [ ] **Step 4: Run tests**

```bash
mix test test/eye_in_the_sky_web/prompts_test.exs 2>&1 | tail -10
```

Expected: 2 tests, 0 failures.

- [ ] **Step 5: Compile check + commit**

```bash
mix compile 2>&1 | grep "error:" | head -5
git add lib/eye_in_the_sky_web/prompts.ex test/eye_in_the_sky_web/prompts_test.exs
git commit -m "feat: guard delete_prompt against FK violation when schedule exists"
```

---

## Chunk 3: UI Components

### Task 5: Create `AgentScheduleForm` component

**Files:**
- Create: `lib/eye_in_the_sky_web_web/components/agent_schedule_form.ex`

- [ ] **Step 1: Create the file**

```elixir
defmodule EyeInTheSkyWebWeb.Components.AgentScheduleForm do
  @moduledoc """
  Scheduling form for agent prompts.
  Drawer on mobile (< sm), centered modal on desktop (>= sm). CSS-only, no JS.
  """

  use Phoenix.Component
  import EyeInTheSkyWebWeb.CoreComponents

  attr :show, :boolean, required: true
  attr :prompt, :any, required: true
  attr :job, :any, default: nil
  attr :projects, :list, required: true
  attr :context_project_id, :any, default: nil

  def agent_schedule_form(assigns) do
    ~H"""
    <%= if @show do %>
      <div class="fixed inset-0 z-40 bg-black/30" phx-click="cancel_schedule"></div>

      <%!-- Mobile drawer --%>
      <div class="sm:hidden fixed inset-y-0 right-0 z-50 w-full max-w-sm bg-base-100 shadow-xl overflow-y-auto">
        <div class="p-5">
          <.form_body prompt={@prompt} job={@job} projects={@projects} context_project_id={@context_project_id} />
        </div>
      </div>

      <%!-- Desktop modal --%>
      <div class="hidden sm:flex fixed inset-0 z-50 items-center justify-center">
        <div class="bg-base-100 rounded-xl shadow-2xl w-full max-w-md p-6 border border-base-300">
          <.form_body prompt={@prompt} job={@job} projects={@projects} context_project_id={@context_project_id} />
        </div>
      </div>
    <% end %>
    """
  end

  attr :prompt, :any, required: true
  attr :job, :any, default: nil
  attr :projects, :list, required: true
  attr :context_project_id, :any, default: nil

  defp form_body(assigns) do
    config =
      case Jason.decode((assigns.job && assigns.job.config) || "{}") do
        {:ok, m} -> m
        _ -> %{}
      end

    assigns =
      assigns
      |> assign(:editing, assigns.job != nil)
      |> assign(:schedule_type, (assigns.job && assigns.job.schedule_type) || "cron")
      |> assign(:schedule_value, (assigns.job && assigns.job.schedule_value) || "")
      |> assign(:model, Map.get(config, "model", "sonnet"))

    ~H"""
    <div class="flex items-start justify-between mb-4">
      <div>
        <h2 class="text-base font-semibold">{if @editing, do: "Edit Schedule", else: "Schedule Agent"}</h2>
        <p class="text-xs text-base-content/50 mt-0.5">{@prompt.name}</p>
        <p class="text-xs text-base-content/40 mt-1 italic">Instructions captured at time of scheduling</p>
      </div>
      <button class="btn btn-ghost btn-sm btn-square" phx-click="cancel_schedule">
        <.icon name="hero-x-mark" class="w-4 h-4" />
      </button>
    </div>

    <form phx-submit="save_schedule" class="space-y-4">
      <input type="hidden" name="schedule[prompt_id]" value={@prompt.id} />
      <%= if @job do %>
        <input type="hidden" name="schedule[job_id]" value={@job.id} />
      <% end %>

      <div class="grid grid-cols-2 gap-3">
        <div class="form-control">
          <label class="label"><span class="label-text text-xs">Schedule Type</span></label>
          <select name="schedule[schedule_type]" class="select select-bordered select-sm w-full">
            <option value="cron" selected={@schedule_type == "cron"}>Cron</option>
            <option value="interval" selected={@schedule_type == "interval"}>Interval</option>
          </select>
        </div>
        <div class="form-control">
          <label class="label"><span class="label-text text-xs">Model</span></label>
          <select name="schedule[model]" class="select select-bordered select-sm w-full">
            <option value="haiku" selected={@model == "haiku"}>Haiku</option>
            <option value="sonnet" selected={@model in ["sonnet", ""]}>Sonnet</option>
            <option value="opus" selected={@model == "opus"}>Opus</option>
          </select>
        </div>
      </div>

      <div class="form-control">
        <label class="label">
          <span class="label-text text-xs">
            {if @schedule_type == "cron", do: "Cron Expression (UTC)", else: "Interval (seconds)"}
          </span>
        </label>
        <input
          type="text"
          name="schedule[schedule_value]"
          value={@schedule_value}
          placeholder={if @schedule_type == "cron", do: "0 5 * * *", else: "3600"}
          class="input input-bordered input-sm w-full font-mono"
          required
        />
      </div>

      <div class="form-control">
        <label class="label"><span class="label-text text-xs">Project (optional override)</span></label>
        <select name="schedule[project_override_id]" class="select select-bordered select-sm w-full">
          <option value="">— use prompt default —</option>
          <%= for p <- @projects do %>
            <option
              value={p.id}
              selected={
                is_nil(@prompt.project_id) &&
                @context_project_id &&
                @context_project_id == p.id
              }
            >
              {p.name}
            </option>
          <% end %>
        </select>
      </div>

      <div class="flex justify-end gap-2 pt-2">
        <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_schedule">Cancel</button>
        <button type="submit" class="btn btn-primary btn-sm">Save Schedule</button>
      </div>
    </form>
    """
  end
end
```

- [ ] **Step 2: Compile check**

```bash
mix compile 2>&1 | grep "error:" | head -10
```

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky_web_web/components/agent_schedule_form.ex
git commit -m "feat: add AgentScheduleForm component (mobile drawer, desktop modal)"
```

---

### Task 6: Create `AgentScheduleHelpers` shared module

**Files:**
- Create: `lib/eye_in_the_sky_web_web/live/shared/agent_schedule_helpers.ex`

- [ ] **Step 1: Verify `Projects` context functions exist**

```bash
grep -n "def list_projects\|def get_project\b" lib/eye_in_the_sky_web/projects.ex
```

If `list_projects/0` or `get_project/1` are missing, add them to `projects.ex` before proceeding:

```elixir
def list_projects do
  Repo.all(from p in Project, order_by: [asc: p.name])
end

def get_project(id) when is_integer(id), do: Repo.get(Project, id)
def get_project(_), do: nil
```

- [ ] **Step 2: Create the helpers module**

```elixir
defmodule EyeInTheSkyWebWeb.Live.Shared.AgentScheduleHelpers do
  @moduledoc """
  Shared event handlers for the Agent Schedules tab.
  Import in OverviewLive.Jobs and ProjectLive.Jobs.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias EyeInTheSkyWeb.{Prompts, ScheduledJobs, Projects}

  @doc "Initialize agent schedule assigns. Call from mount/3."
  def assign_agent_schedule_defaults(socket) do
    assign(socket,
      active_tab: :all_jobs,
      prompts: [],
      prompt_job_map: %{},
      scheduling_prompt: nil,
      scheduling_job: nil,
      orphaned_jobs: [],
      projects: Projects.list_projects()
    )
  end

  def handle_switch_tab(%{"tab" => "agent_schedules"}, socket) do
    {:noreply, socket |> assign(:active_tab, :agent_schedules) |> load_agent_schedule_data()}
  end

  def handle_switch_tab(%{"tab" => "all_jobs"}, socket) do
    {:noreply, assign(socket, :active_tab, :all_jobs)}
  end

  def handle_switch_tab(_, socket), do: {:noreply, socket}

  def handle_schedule_prompt(%{"id" => id}, socket) do
    prompt = Prompts.get_prompt!(String.to_integer(id))
    {:noreply, socket |> assign(:scheduling_prompt, prompt) |> assign(:scheduling_job, nil)}
  end

  def handle_edit_schedule(%{"job_id" => job_id}, socket) do
    job = ScheduledJobs.get_job!(String.to_integer(job_id))
    prompt = if job.prompt_id, do: Prompts.get_prompt!(job.prompt_id), else: nil
    {:noreply, socket |> assign(:scheduling_prompt, prompt) |> assign(:scheduling_job, job)}
  end

  def handle_cancel_schedule(_params, socket) do
    {:noreply, socket |> assign(:scheduling_prompt, nil) |> assign(:scheduling_job, nil)}
  end

  def handle_save_schedule(%{"schedule" => params}, socket) do
    prompt_id = String.to_integer(params["prompt_id"])
    prompt = Prompts.get_prompt!(prompt_id)

    case resolve_project_path(params, prompt, socket) do
      {:error, :no_project} ->
        {:noreply, put_flash(socket, :error, "Could not resolve project path. Select a project override.")}

      {:ok, path} ->
        config = Jason.encode!(%{
          "prompt_id" => prompt_id,
          "instructions" => prompt.prompt_text,
          "model" => params["model"] || "sonnet",
          "project_path" => path
        })

        job_attrs = %{
          "name" => prompt.name,
          "description" => prompt.description || "",
          "job_type" => "spawn_agent",
          "schedule_type" => params["schedule_type"],
          "schedule_value" => params["schedule_value"],
          "config" => config,
          "prompt_id" => prompt_id,
          "enabled" => 1
        }

        result =
          if params["job_id"] && params["job_id"] != "" do
            job = ScheduledJobs.get_job!(String.to_integer(params["job_id"]))
            ScheduledJobs.update_job(job, job_attrs)
          else
            ScheduledJobs.create_job(job_attrs)
          end

        case result do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:scheduling_prompt, nil)
             |> assign(:scheduling_job, nil)
             |> load_agent_schedule_data()
             |> put_flash(:info, "Schedule saved")}

          {:error, :already_scheduled} ->
            {:noreply, put_flash(socket, :error, "This agent already has a schedule")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to save schedule")}
        end
    end
  end

  @doc "Call from handle_info(:jobs_updated) to refresh data when tab is active."
  def maybe_reload_agent_schedule_data(socket) do
    if socket.assigns.active_tab == :agent_schedules do
      load_agent_schedule_data(socket)
    else
      socket
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp load_agent_schedule_data(socket) do
    prompts = load_prompts_for_context(socket)
    prompt_ids = Enum.map(prompts, & &1.id)
    jobs = ScheduledJobs.list_spawn_agent_jobs_by_prompt_ids(prompt_ids)
    prompt_job_map = Map.new(jobs, fn j -> {j.prompt_id, j} end)
    orphaned_jobs = ScheduledJobs.list_orphaned_agent_jobs()

    assign(socket,
      prompts: prompts,
      prompt_job_map: prompt_job_map,
      orphaned_jobs: orphaned_jobs
    )
  end

  defp load_prompts_for_context(socket) do
    case Map.get(socket.assigns, :project_id) do
      nil -> Prompts.list_global_prompts()
      project_id -> Prompts.list_prompts(project_id: project_id)
    end
  end

  # 4-step resolution: form override → prompt default → page context → error
  defp resolve_project_path(params, prompt, socket) do
    override_id = params["project_override_id"]

    cond do
      override_id && override_id != "" ->
        project = Projects.get_project(String.to_integer(override_id))
        if project && project.path, do: {:ok, project.path}, else: {:error, :no_project}

      prompt.project_id ->
        project = Projects.get_project(prompt.project_id)
        if project && project.path, do: {:ok, project.path}, else: {:error, :no_project}

      project_id = Map.get(socket.assigns, :project_id) ->
        project = Projects.get_project(project_id)
        if project && project.path, do: {:ok, project.path}, else: {:error, :no_project}

      true ->
        {:error, :no_project}
    end
  end
end
```

- [ ] **Step 3: Compile check**

```bash
mix compile 2>&1 | grep "error:" | head -10
```

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/shared/agent_schedule_helpers.ex
git commit -m "feat: add AgentScheduleHelpers shared module for schedule event handling"
```

---

## Chunk 4: LiveView Integration

### Task 7: Update `OverviewLive.Jobs`

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/overview_live/jobs.ex`

- [ ] **Step 1: Add imports and alias**

At the top of the module, alongside existing aliases/imports, add:

```elixir
alias EyeInTheSkyWeb.Prompts.Prompt   # needed for the fallback struct in render
import EyeInTheSkyWebWeb.Live.Shared.AgentScheduleHelpers
import EyeInTheSkyWebWeb.Components.AgentScheduleForm
```

Note: `run_now` and `delete_job` event handlers already exist in both LiveViews — no changes needed for those.

- [ ] **Step 2: Add new assigns to `mount/3`**

After the last existing `assign(...)` call in `mount/3`, add:

```elixir
|> assign_agent_schedule_defaults()
```

- [ ] **Step 3: Update `handle_info(:jobs_updated)`**

```elixir
@impl true
def handle_info(:jobs_updated, socket) do
  socket =
    socket
    |> assign(:jobs, ScheduledJobs.list_jobs())
    |> maybe_reload_agent_schedule_data()

  {:noreply, socket}
end
```

- [ ] **Step 4: Add event handlers**

```elixir
@impl true
def handle_event("switch_tab", params, socket),
  do: handle_switch_tab(params, socket)

@impl true
def handle_event("schedule_prompt", params, socket),
  do: handle_schedule_prompt(params, socket)

@impl true
def handle_event("edit_schedule", params, socket),
  do: handle_edit_schedule(params, socket)

@impl true
def handle_event("cancel_schedule", params, socket),
  do: handle_cancel_schedule(params, socket)

@impl true
def handle_event("save_schedule", params, socket),
  do: handle_save_schedule(params, socket)
```

- [ ] **Step 5: Update `render/1` — add tabs**

In the `render` function, find the page header section. Add the tab bar immediately after it:

```heex
<div class="flex border-b border-base-300 px-4">
  <button
    class={"tab tab-bordered #{if @active_tab == :all_jobs, do: "tab-active"}"}
    phx-click="switch_tab" phx-value-tab="all_jobs"
  >
    All Jobs
  </button>
  <button
    class={"tab tab-bordered #{if @active_tab == :agent_schedules, do: "tab-active"}"}
    phx-click="switch_tab" phx-value-tab="agent_schedules"
  >
    Agent Schedules
  </button>
</div>
```

- [ ] **Step 6: Wrap existing jobs list**

Wrap the existing jobs list/table content in:

```heex
<%= if @active_tab == :all_jobs do %>
  <%!-- existing jobs content here --%>
<% end %>
```

- [ ] **Step 7: Add Agent Schedules panel**

After the wrapped jobs content:

```heex
<%= if @active_tab == :agent_schedules do %>
  <div class="p-4 space-y-6">
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
      <%= for prompt <- @prompts do %>
        <% job = Map.get(@prompt_job_map, prompt.id) %>
        <div class={"card bg-base-200 border #{if job, do: "border-primary", else: "border-base-300"}"}>
          <div class="card-body p-4 gap-2">
            <div class="flex items-start justify-between">
              <h3 class="font-semibold text-sm leading-tight">{prompt.name}</h3>
              <%= if job do %>
                <span class="badge badge-success badge-xs whitespace-nowrap">● active</span>
              <% end %>
            </div>
            <p class="text-xs text-base-content/60 line-clamp-2">{prompt.description}</p>
            <div class="flex items-center justify-between mt-1">
              <%= if job do %>
                <span class="font-mono text-xs text-base-content/50">{job.schedule_value}</span>
                <div class="flex gap-1">
                  <button class="btn btn-ghost btn-xs" phx-click="edit_schedule" phx-value-job_id={job.id}>Edit</button>
                  <button class="btn btn-ghost btn-xs" phx-click="run_now" phx-value-id={job.id}>▶</button>
                </div>
              <% else %>
                <span class="text-xs text-base-content/40">not scheduled</span>
                <button class="btn btn-primary btn-xs" phx-click="schedule_prompt" phx-value-id={prompt.id}>+ Schedule</button>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>

    <%= if @orphaned_jobs != [] do %>
      <div>
        <p class="text-xs font-semibold uppercase tracking-wide text-base-content/40 mb-2">Detached Schedules</p>
        <div class="space-y-2">
          <%= for job <- @orphaned_jobs do %>
            <div class="flex items-center gap-3 p-3 rounded-lg bg-base-200 border border-warning/40">
              <div class="flex-1 min-w-0">
                <span class="text-sm truncate">{job.name}</span>
                <span class="badge badge-warning badge-xs ml-2">Prompt deactivated</span>
              </div>
              <span class="font-mono text-xs text-base-content/50 shrink-0">{job.schedule_value}</span>
              <button class="btn btn-ghost btn-xs" phx-click="run_now" phx-value-id={job.id}>▶</button>
              <button class="btn btn-ghost btn-xs text-error" phx-click="delete_job" phx-value-id={job.id}>Delete</button>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 8: Add form component at the bottom of render**

Just before the closing `</div>` of the root element in `render`:

```heex
<.agent_schedule_form
  show={@scheduling_prompt != nil}
  prompt={@scheduling_prompt || %EyeInTheSkyWeb.Prompts.Prompt{name: ""}}
  job={@scheduling_job}
  projects={@projects}
/>
```

- [ ] **Step 9: Compile check**

```bash
mix compile 2>&1 | grep "error:" | head -10
```

- [ ] **Step 10: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/overview_live/jobs.ex
git commit -m "feat: add Agent Schedules tab to OverviewLive.Jobs"
```

---

### Task 8: Update `ProjectLive.Jobs`

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/project_live/jobs.ex`

- [ ] **Step 1: Mirror Task 7 steps 1–4**

Add the same imports, `assign_agent_schedule_defaults()` in mount, updated `handle_info`, and five event handler delegates.

For `ProjectLive.Jobs`, `mount/3` already sets `project_id` in assigns (via `mount_project/3`), so `load_prompts_for_context/1` will automatically load project-scoped prompts.

- [ ] **Step 2: Update `handle_info(:jobs_updated)`**

```elixir
@impl true
def handle_info(:jobs_updated, socket) do
  socket =
    socket
    |> reload_jobs()
    |> maybe_reload_agent_schedule_data()

  {:noreply, socket}
end
```

- [ ] **Step 3: Add tabs + agent schedule panel to render**

Same as Task 7, steps 5–8. For the form component, pass `context_project_id`:

```heex
<.agent_schedule_form
  show={@scheduling_prompt != nil}
  prompt={@scheduling_prompt || %EyeInTheSkyWeb.Prompts.Prompt{name: ""}}
  job={@scheduling_job}
  projects={@projects}
  context_project_id={Map.get(assigns, :project_id)}
/>
```

- [ ] **Step 4: Compile check**

```bash
mix compile 2>&1 | grep "error:" | head -10
```

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/project_live/jobs.ex
git commit -m "feat: add Agent Schedules tab to ProjectLive.Jobs"
```

---

### Task 9: Verify prompt deletion path (no LiveView changes needed)

The prompt LiveViews (`prompt_live/index.ex`, `prompt_live/show.ex`) both call `Prompts.deactivate_prompt/1` — a soft-delete that sets `active = false`. This **does not** hit the FK constraint since the row stays in the DB. The `delete_prompt/1` FK guard (Task 4) protects direct hard-deletes from the API or scripts.

The "Detached Schedules" section works via soft-deactivation: deactivating a prompt sets `active = false`, `list_orphaned_agent_jobs/0` picks it up, the card disappears from the main grid and appears in Detached Schedules. No UI changes are needed.

- [ ] **Step 1: Confirm soft-delete is the only UI deletion path**

```bash
grep -n "delete_prompt\|deactivate_prompt" lib/eye_in_the_sky_web_web/live/prompt_live/*.ex
```

Expected: only `deactivate_prompt` calls, no `delete_prompt` calls.

- [ ] **Step 2: Smoke test the deactivation flow**

1. Create a schedule for a prompt via the Agent Schedules tab.
2. Go to the Prompts page and "delete" (deactivate) that prompt.
3. Return to Jobs → Agent Schedules tab.
4. Confirm the card is gone from the main grid and appears in "Detached Schedules" with the "Prompt deactivated" badge.

No code changes or commit needed for this task.

---

## Final Verification

- [ ] **Run full test suite**

```bash
mix test 2>&1 | tail -20
```

Expected: All existing tests pass; new tests added in Chunks 1–2 pass.

- [ ] **Compile with warnings-as-errors**

```bash
mix compile --warnings-as-errors 2>&1 | tail -10
```

Expected: exits 0.

- [ ] **Verify SpawnAgentWorker config keys match**

```bash
grep -n 'config\[' lib/eye_in_the_sky_web/workers/spawn_agent_worker.ex
```

Confirm: `config["instructions"]`, `config["model"]`, `config["project_path"]` — all match the config shape written in `handle_save_schedule`. ✓

- [ ] **Manual smoke test checklist**

1. Open `http://localhost:5000/jobs` → click "Agent Schedules" tab → prompt cards appear
2. Click "+ Schedule" on a card → form opens (drawer on mobile, modal on desktop)
3. Fill cron + model, save → card shows "● active"
4. Click "+ Schedule" on same card again → flash "This agent already has a schedule"
5. Open Prompts page, try deleting a scheduled prompt → flash "Delete the schedule first"
6. Deactivate that prompt → disappears from card grid, appears in "Detached Schedules"
7. Open a project's Jobs page → only that project's + global prompts shown in Agent Schedules tab

- [ ] **Commit plan doc**

```bash
git add docs/superpowers/plans/2026-03-16-agent-schedules.md
git commit -m "docs: add agent schedules implementation plan"
```
