defmodule EyeInTheSkyWeb.OverviewLive.JobsTest do
  # TODO: No LiveView at /jobs — only a REST controller (JobController) handles that route.
  # These tests need to be rewritten against the project-scoped /projects/:id/jobs LiveView,
  # or a global jobs LiveView needs to be implemented.
  use EyeInTheSkyWeb.ConnCase, async: false

  @moduletag :skip

  import Phoenix.LiveViewTest

  alias EyeInTheSky.ScheduledJobs

  defp job_attrs(overrides) do
    Map.merge(
      %{
        "name" => "Test Job",
        "job_type" => "shell_command",
        "schedule_type" => "interval",
        "schedule_value" => "60",
        "config" => Jason.encode!(%{"command" => "echo hello", "working_dir" => "/tmp"})
      },
      overrides
    )
  end

  describe "mount" do
    test "mounts without crashing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/jobs")
      assert has_element?(view, "h1", "Scheduled Jobs")
    end

    test "shows empty state when no jobs exist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/jobs")
      assert has_element?(view, "h3", "No scheduled jobs")
    end

    test "lists all jobs across projects", %{conn: conn} do
      {:ok, _} = ScheduledJobs.create_job(job_attrs(%{"name" => "Global Shell Job"}))

      {:ok, view, _html} = live(conn, ~p"/jobs")
      assert has_element?(view, "span.font-medium", "Global Shell Job")
    end

    test "renders tab bar with All Jobs and Schedule Agents tabs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/jobs")
      assert has_element?(view, "button[phx-value-tab='all_jobs']", "All Jobs")
      assert has_element?(view, "button[phx-value-tab='agent_schedules']", "Schedule Agents")
    end

    test "renders New Job button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/jobs")
      assert has_element?(view, "button[phx-click='new_job']", "+ New Job")
    end
  end
end
