defmodule EyeInTheSkyWeb.Live.Shared.AgentScheduleHelpersTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import EyeInTheSky.Factory

  alias EyeInTheSky.{Prompts, ScheduledJobs}
  alias EyeInTheSkyWeb.Live.Shared.AgentScheduleHelpers

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp unique_n, do: System.unique_integer([:positive])

  defp bare_socket(extra_assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns:
        Map.merge(
          %{
            active_tab: :all_jobs,
            prompts: [],
            prompt_job_map: %{},
            scheduling_prompt: nil,
            scheduling_job: nil,
            orphaned_jobs: [],
            projects: [],
            flash: %{},
            __changed__: %{}
          },
          extra_assigns
        )
    }
  end

  defp create_prompt(attrs \\ %{}) do
    n = uniq()
    project = project_fixture()

    defaults = %{
      name: "prompt-#{n}",
      slug: "prompt-#{n}",
      prompt_text: "Do something #{n}",
      project_id: project.id
    }

    {:ok, prompt} = Prompts.create_prompt(Map.merge(defaults, attrs))
    {prompt, project}
  end

  defp create_job(attrs \\ %{}) do
    n = uniq()

    defaults = %{
      "name" => "job-#{n}",
      "description" => "",
      "job_type" => "spawn_agent",
      "schedule_type" => "interval",
      "schedule_value" => "3600",
      "config" => "{}",
      "enabled" => true
    }

    {:ok, job} = ScheduledJobs.create_job(Map.merge(defaults, attrs))
    job
  end

  # ---------------------------------------------------------------------------
  # assign_agent_schedule_defaults/1
  # ---------------------------------------------------------------------------

  describe "assign_agent_schedule_defaults/1" do
    test "sets active_tab to :all_jobs" do
      socket = bare_socket()
      result = AgentScheduleHelpers.assign_agent_schedule_defaults(socket)
      assert result.assigns.active_tab == :all_jobs
    end

    test "initializes prompts as empty list" do
      socket = bare_socket()
      result = AgentScheduleHelpers.assign_agent_schedule_defaults(socket)
      assert result.assigns.prompts == []
    end

    test "initializes prompt_job_map as empty map" do
      socket = bare_socket()
      result = AgentScheduleHelpers.assign_agent_schedule_defaults(socket)
      assert result.assigns.prompt_job_map == %{}
    end

    test "initializes scheduling_prompt and scheduling_job as nil" do
      socket = bare_socket()
      result = AgentScheduleHelpers.assign_agent_schedule_defaults(socket)
      assert result.assigns.scheduling_prompt == nil
      assert result.assigns.scheduling_job == nil
    end

    test "initializes orphaned_jobs as empty list" do
      socket = bare_socket()
      result = AgentScheduleHelpers.assign_agent_schedule_defaults(socket)
      assert result.assigns.orphaned_jobs == []
    end

    test "populates projects from Projects.list_projects/0" do
      # Create a project so there's at least one to list
      project_fixture()
      socket = bare_socket()
      result = AgentScheduleHelpers.assign_agent_schedule_defaults(socket)
      assert is_list(result.assigns.projects)
      assert length(result.assigns.projects) > 0
    end
  end

  # ---------------------------------------------------------------------------
  # handle_switch_tab/2
  # ---------------------------------------------------------------------------

  describe "handle_switch_tab/2" do
    test "switching to all_jobs sets active_tab to :all_jobs" do
      socket = bare_socket(%{active_tab: :agent_schedules})
      {:noreply, result} = AgentScheduleHelpers.handle_switch_tab(%{"tab" => "all_jobs"}, socket)
      assert result.assigns.active_tab == :all_jobs
    end

    test "switching to agent_schedules sets active_tab to :agent_schedules" do
      socket = bare_socket()
      {:noreply, result} =
        AgentScheduleHelpers.handle_switch_tab(%{"tab" => "agent_schedules"}, socket)

      assert result.assigns.active_tab == :agent_schedules
    end

    test "unknown tab param is a no-op" do
      socket = bare_socket(%{active_tab: :all_jobs})
      {:noreply, result} =
        AgentScheduleHelpers.handle_switch_tab(%{"tab" => "nonexistent_tab"}, socket)

      assert result.assigns.active_tab == :all_jobs
    end

    test "switching to agent_schedules loads prompts list" do
      {_prompt, _project} = create_prompt()
      socket = bare_socket()

      {:noreply, result} =
        AgentScheduleHelpers.handle_switch_tab(%{"tab" => "agent_schedules"}, socket)

      assert is_list(result.assigns.prompts)
    end

    test "switching to agent_schedules loads prompt_job_map" do
      socket = bare_socket()

      {:noreply, result} =
        AgentScheduleHelpers.handle_switch_tab(%{"tab" => "agent_schedules"}, socket)

      assert is_map(result.assigns.prompt_job_map)
    end
  end

  # ---------------------------------------------------------------------------
  # handle_cancel_schedule/2
  # ---------------------------------------------------------------------------

  describe "handle_cancel_schedule/2" do
    test "clears scheduling_prompt to nil" do
      {prompt, _} = create_prompt()
      socket = bare_socket(%{scheduling_prompt: prompt, scheduling_job: nil})

      {:noreply, result} = AgentScheduleHelpers.handle_cancel_schedule(%{}, socket)

      assert result.assigns.scheduling_prompt == nil
    end

    test "clears scheduling_job to nil" do
      job = create_job()
      socket = bare_socket(%{scheduling_prompt: nil, scheduling_job: job})

      {:noreply, result} = AgentScheduleHelpers.handle_cancel_schedule(%{}, socket)

      assert result.assigns.scheduling_job == nil
    end

    test "clears both prompt and job simultaneously" do
      {prompt, _} = create_prompt()
      job = create_job()
      socket = bare_socket(%{scheduling_prompt: prompt, scheduling_job: job})

      {:noreply, result} = AgentScheduleHelpers.handle_cancel_schedule(%{}, socket)

      assert result.assigns.scheduling_prompt == nil
      assert result.assigns.scheduling_job == nil
    end
  end

  # ---------------------------------------------------------------------------
  # handle_schedule_prompt/2
  # ---------------------------------------------------------------------------

  describe "handle_schedule_prompt/2" do
    test "sets scheduling_prompt to the resolved DB prompt" do
      {prompt, _} = create_prompt()
      socket = bare_socket()

      {:noreply, result} =
        AgentScheduleHelpers.handle_schedule_prompt(%{"id" => to_string(prompt.id)}, socket)

      assert result.assigns.scheduling_prompt.id == prompt.id
    end

    test "clears scheduling_job when scheduling a prompt" do
      {prompt, _} = create_prompt()
      existing_job = create_job()
      socket = bare_socket(%{scheduling_job: existing_job})

      {:noreply, result} =
        AgentScheduleHelpers.handle_schedule_prompt(%{"id" => to_string(prompt.id)}, socket)

      assert result.assigns.scheduling_job == nil
    end

    test "puts error flash for unknown prompt id" do
      socket = bare_socket()

      {:noreply, result} =
        AgentScheduleHelpers.handle_schedule_prompt(%{"id" => "99999999"}, socket)

      assert result.assigns.flash["error"] =~ "Agent not found"
    end

    test "puts error flash for nil id" do
      socket = bare_socket()
      {:noreply, result} = AgentScheduleHelpers.handle_schedule_prompt(%{"id" => nil}, socket)
      assert result.assigns.flash["error"] =~ "Agent not found"
    end

    test "puts error flash for empty string id" do
      socket = bare_socket()
      {:noreply, result} = AgentScheduleHelpers.handle_schedule_prompt(%{"id" => ""}, socket)
      assert result.assigns.flash["error"] =~ "Agent not found"
    end
  end

  # ---------------------------------------------------------------------------
  # handle_edit_schedule/2
  # ---------------------------------------------------------------------------

  describe "handle_edit_schedule/2" do
    test "puts error flash for invalid job_id" do
      socket = bare_socket()

      {:noreply, result} =
        AgentScheduleHelpers.handle_edit_schedule(%{"job_id" => "not_an_int"}, socket)

      assert result.assigns.flash["error"] =~ "Invalid job ID"
    end

    test "puts error flash for non-existent job_id" do
      socket = bare_socket()

      {:noreply, result} =
        AgentScheduleHelpers.handle_edit_schedule(%{"job_id" => "99999999"}, socket)

      assert result.assigns.flash["error"] =~ "Job not found"
    end

    test "puts error flash when job is not accessible from project-scoped page" do
      # Create a job with no project_id (global job) but put a project_id on socket
      job = create_job()
      project = project_fixture()
      socket = bare_socket(%{project_id: project.id})

      {:noreply, result} =
        AgentScheduleHelpers.handle_edit_schedule(%{"job_id" => to_string(job.id)}, socket)

      # job.project_id is nil, socket.project_id is set — access denied
      assert result.assigns.flash["error"] =~ "Access denied"
    end

    test "allows editing a global job from the overview page (no project_id in assigns)" do
      # A job with no prompt_id and no agent_file_id in config will resolve nil prompt.
      # We only test that the function doesn't flash an error when the job IS accessible.
      job = create_job()
      socket = bare_socket()  # no project_id in assigns => overview context

      {:noreply, result} =
        AgentScheduleHelpers.handle_edit_schedule(%{"job_id" => to_string(job.id)}, socket)

      # Should not have an error flash for access
      refute Map.has_key?(result.assigns.flash, "error")
    end
  end

  # ---------------------------------------------------------------------------
  # maybe_reload_agent_schedule_data/1
  # ---------------------------------------------------------------------------

  describe "maybe_reload_agent_schedule_data/1" do
    test "reloads data when active_tab is :agent_schedules" do
      socket = bare_socket(%{active_tab: :agent_schedules})
      result = AgentScheduleHelpers.maybe_reload_agent_schedule_data(socket)

      # should return a socket with prompts/prompt_job_map populated
      assert is_list(result.assigns.prompts)
      assert is_map(result.assigns.prompt_job_map)
    end

    test "is a no-op when active_tab is not :agent_schedules" do
      original_prompts = ["sentinel"]
      socket = bare_socket(%{active_tab: :all_jobs, prompts: original_prompts})
      result = AgentScheduleHelpers.maybe_reload_agent_schedule_data(socket)

      # prompts should be untouched
      assert result.assigns.prompts == original_prompts
    end
  end
end
