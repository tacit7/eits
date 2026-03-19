defmodule EyeInTheSkyWebWeb.OverviewLive.JobsTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.ScheduledJobs

  defp job_attrs(overrides \\ %{}) do
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
      {:ok, _view, html} = live(conn, ~p"/jobs")
      assert html =~ "Scheduled Jobs"
    end

    test "shows empty state when no jobs exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/jobs")
      assert html =~ "No scheduled jobs"
    end

    test "lists all jobs across projects", %{conn: conn} do
      {:ok, _} = ScheduledJobs.create_job(job_attrs(%{"name" => "Global Shell Job"}))

      {:ok, _view, html} = live(conn, ~p"/jobs")
      assert html =~ "Global Shell Job"
    end

    test "renders tab bar with All Jobs and Schedule Agents tabs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/jobs")
      assert html =~ "All Jobs"
      assert html =~ "Schedule Agents"
    end

    test "renders New Job button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/jobs")
      assert html =~ "+ New Job"
    end
  end
end
