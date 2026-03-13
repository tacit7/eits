defmodule EyeInTheSkyWebWeb.ProjectLive.JobsTest do
  use EyeInTheSkyWebWeb.ConnCase

  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.{Projects, ScheduledJobs}

  setup do
    {:ok, project} =
      Projects.create_project(%{
        name: "test-project",
        path: "/tmp/test-project",
        slug: "test-project"
      })

    %{project: project}
  end

  defp job_attrs(project_id, overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Test Job",
        "job_type" => "shell_command",
        "schedule_type" => "interval",
        "schedule_value" => "60",
        "project_id" => project_id,
        "config" => Jason.encode!(%{"command" => "echo hello", "working_dir" => "/tmp"})
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
      {:ok, other_project} =
        Projects.create_project(%{name: "other", path: "/tmp/other", slug: "other"})

      {:ok, _} = ScheduledJobs.create_job(job_attrs(project.id, %{"name" => "My Job"}))
      {:ok, _} = ScheduledJobs.create_job(job_attrs(other_project.id, %{"name" => "Other Job"}))

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/jobs")
      assert html =~ "My Job"
      refute html =~ "Other Job"
    end

    test "shows global (null project_id) jobs in a separate section", %{conn: conn, project: project} do
      {:ok, _} =
        ScheduledJobs.create_job(%{
          "name" => "Global Job",
          "job_type" => "shell_command",
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
        "job[job_type]" => "shell_command",
        "job[schedule_type]" => "interval",
        "job[schedule_value]" => "120"
      })
      |> render_submit()

      jobs = ScheduledJobs.list_jobs_for_project(project.id)
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
        "job[job_type]" => "shell_command",
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
      |> element("input[type='checkbox'][phx-value-id='#{job.id}']")
      |> render_click()

      {:ok, updated} = ScheduledJobs.get_job(job.id)
      assert updated.enabled == 0
    end

    test "run now button triggers job", %{conn: conn, project: project, job: job} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")

      view
      |> element("button[phx-click='run_now'][phx-value-id='#{job.id}']")
      |> render_click()

      assert render(view) =~ "Job triggered"
    end

    test "delete removes job from list", %{conn: conn, project: project, job: job} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/jobs")

      view
      |> element("button[phx-click='delete_job'][phx-value-id='#{job.id}']")
      |> render_click()

      refute render(view) =~ job.name
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
end
