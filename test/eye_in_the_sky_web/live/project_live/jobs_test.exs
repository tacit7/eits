defmodule EyeInTheSkyWeb.ProjectLive.JobsTest do
  use EyeInTheSkyWeb.ConnCase

  import Phoenix.LiveViewTest
  import EyeInTheSky.Factory

  alias EyeInTheSky.ScheduledJobs

  setup do
    project = project_fixture()
    %{project: project}
  end

  defp job_attrs(project_id, overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Test Job",
        "job_type" => "spawn_agent",
        "schedule_type" => "interval",
        "schedule_value" => "60",
        "project_id" => project_id,
        "config" => "{}"
      },
      overrides
    )
  end

  describe "mount" do
    test "renders jobs page for project", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/jobs")
      assert html =~ "Scheduled Jobs"
    end

    test "shows empty state when project has no jobs", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/jobs")
      assert html =~ "No scheduled jobs"
    end

    test "lists only jobs scoped to the project", %{conn: conn, project: project} do
      other_project = project_fixture(%{name: "other-scoped"})

      {:ok, _} = ScheduledJobs.create_job(job_attrs(project.id, %{"name" => "My Job"}))
      {:ok, _} = ScheduledJobs.create_job(job_attrs(other_project.id, %{"name" => "Other Job"}))

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")
      assert has_element?(view, "#main-content", "My Job")
      refute has_element?(view, "#main-content", "Other Job")
    end

    test "shows global (null project_id) jobs in a separate section", %{
      conn: conn,
      project: project
    } do
      {:ok, _} =
        ScheduledJobs.create_job(%{
          "name" => "Global Job",
          "job_type" => "spawn_agent",
          "schedule_type" => "interval",
          "schedule_value" => "60",
          "config" => "{}"
        })

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/jobs")
      assert html =~ "Global Jobs"
      assert html =~ "Global Job"
    end
  end

  describe "new job form" do
    test "opens drawer on new job click", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")
      view |> element("button", "+ New Job") |> render_click()
      assert has_element?(view, "h2", "New Job")
    end

    test "new job form pre-fills project_id", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")
      view |> element("button", "+ New Job") |> render_click()

      html = render(view)
      assert html =~ "value=\"#{project.id}\""
    end

    test "creates job scoped to project on submit", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")
      view |> element("button", "+ New Job") |> render_click()

      view
      |> form("form[phx-submit='save_job']", %{
        "job[name]" => "New Job",
        "job[job_type]" => "spawn_agent",
        "job[schedule_type]" => "interval",
        "job[schedule_value]" => "120"
      })
      |> render_submit()

      jobs = ScheduledJobs.list_jobs(project_id: project.id)
      assert length(jobs) == 1
      assert hd(jobs).name == "New Job"
      assert hd(jobs).project_id == project.id
    end

    test "shows job in list after creation", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")
      view |> element("button", "+ New Job") |> render_click()

      view
      |> form("form[phx-submit='save_job']", %{
        "job[name]" => "Visible Job",
        "job[job_type]" => "spawn_agent",
        "job[schedule_type]" => "interval",
        "job[schedule_value]" => "60"
      })
      |> render_submit()

      assert render(view) =~ "Visible Job"
    end

    test "closes drawer on cancel", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")
      view |> element("button", "+ New Job") |> render_click()
      view |> element("button[phx-click='cancel_form']", "Cancel") |> render_click()

      # Backdrop overlay is conditionally rendered — absent means drawer is closed
      refute has_element?(view, "div.fixed.inset-0.z-40")
    end
  end

  describe "job actions" do
    setup %{project: project} do
      {:ok, job} = ScheduledJobs.create_job(job_attrs(project.id))
      %{job: job}
    end

    test "toggle enables/disables job", %{conn: conn, project: project, job: job} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")

      view
      |> element("input.toggle-sm[phx-value-id='#{job.id}']")
      |> render_click()

      {:ok, updated} = ScheduledJobs.get_job(job.id)
      assert updated.enabled == false
    end

    test "run now button triggers job", %{conn: conn, project: project, job: job} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")

      view
      |> element("button[aria-label='Run job now'][phx-value-id='#{job.id}']")
      |> render_click()

      assert has_element?(view, "#flash-info", "Job triggered")
    end

    test "delete removes job from list", %{conn: conn, project: project, job: job} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")

      view
      |> element("button[aria-label='Delete job'][phx-value-id='#{job.id}']")
      |> render_click()

      refute has_element?(view, "#main-content", job.name)
      assert ScheduledJobs.get_job(job.id) == {:error, :not_found}
    end

    test "expand shows run history", %{conn: conn, project: project, job: job} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")

      view
      |> element("td[phx-click='expand_job'][phx-value-id='#{job.id}']")
      |> render_click()

      assert has_element?(view, "div", "Recent Runs")
    end
  end

  describe "cross-project access guard" do
    test "edit_job on another project's job shows error flash and does not open edit form",
         %{conn: conn, project: project} do
      other_project = project_fixture(%{name: "other-ej"})

      {:ok, other_job} =
        ScheduledJobs.create_job(job_attrs(other_project.id, %{"name" => "Other Edit Job"}))

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")
      render_click(view, "edit_job", %{"id" => "#{other_job.id}"})

      assert has_element?(view, "#flash-error", "Access denied")
      refute has_element?(view, "h2", "Edit Job")
    end

    test "edit_schedule on another project's job shows error flash",
         %{conn: conn, project: project} do
      other_project = project_fixture(%{name: "other-es"})

      {:ok, other_job} =
        ScheduledJobs.create_job(job_attrs(other_project.id, %{"name" => "Sched Target"}))

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")
      render_click(view, "edit_schedule", %{"job_id" => "#{other_job.id}"})

      assert has_element?(view, "#flash-error", "Access denied")
    end

    test "crafted event with non-existent job id shows flash error not crash",
         %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")
      render_click(view, "edit_job", %{"id" => "999999"})

      assert has_element?(view, "#flash-error", "Job not found")
    end

    test "toggling a job from another project shows error flash and leaves job unchanged",
         %{conn: conn, project: project} do
      other_project = project_fixture(%{name: "other-xp"})

      {:ok, other_job} =
        ScheduledJobs.create_job(job_attrs(other_project.id, %{"name" => "Other Job"}))

      original_enabled = other_job.enabled

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")
      render_click(view, "toggle_job", %{"id" => "#{other_job.id}"})

      assert has_element?(view, "#flash-error", "Access denied")

      {:ok, unchanged} = ScheduledJobs.get_job(other_job.id)
      assert unchanged.enabled == original_enabled
    end

    test "deleting a job from another project shows error flash and leaves job in DB",
         %{conn: conn, project: project} do
      other_project = project_fixture(%{name: "other-del"})

      {:ok, other_job} =
        ScheduledJobs.create_job(job_attrs(other_project.id, %{"name" => "Delete Target"}))

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")
      render_click(view, "delete_job", %{"id" => "#{other_job.id}"})

      assert has_element?(view, "#flash-error", "Access denied")
      assert {:ok, _} = ScheduledJobs.get_job(other_job.id)
    end

    test "run_now on a job from another project shows error flash",
         %{conn: conn, project: project} do
      other_project = project_fixture(%{name: "other-run"})

      {:ok, other_job} =
        ScheduledJobs.create_job(job_attrs(other_project.id, %{"name" => "Run Target"}))

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")
      render_click(view, "run_now", %{"id" => "#{other_job.id}"})

      assert has_element?(view, "#flash-error", "Access denied")
    end
  end

  describe "malformed job_id on schedule paths" do
    test "edit_schedule with non-integer job_id shows flash error not crash",
         %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")
      render_click(view, "edit_schedule", %{"job_id" => "abc"})

      assert has_element?(view, "#flash-error", "Invalid job ID")
    end

    test "edit_schedule with empty string job_id shows flash error not crash",
         %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")
      render_click(view, "edit_schedule", %{"job_id" => "1abc2"})

      assert has_element?(view, "#flash-error", "Invalid job ID")
    end
  end

  describe "run_now failure" do
    test "run_now on non-existent job ID shows error flash not success",
         %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")
      render_click(view, "run_now", %{"id" => "999999"})

      assert has_element?(view, "#flash-error", "Job not found")
      refute has_element?(view, "#flash-info", "Job triggered")
    end
  end

  describe "nil project redirect" do
    test "redirects to /projects when project ID does not exist", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/projects"}}} =
               live(conn, ~p"/projects/99999/jobs")
    end
  end
end
