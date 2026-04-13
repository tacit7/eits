defmodule EyeInTheSkyWeb.Api.V1.JobControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Accounts.ApiKey
  alias EyeInTheSky.ScheduledJobs

  defp api_conn do
    token = "test_api_key_#{System.unique_integer([:positive])}"
    {:ok, _} = ApiKey.create(token, "test")
    Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end

  defp valid_job_params(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Test job #{System.unique_integer([:positive])}",
        "job_type" => "mix_task",
        "schedule_type" => "interval",
        "schedule_value" => "3600",
        "config" => Jason.encode!(%{"task" => "my_app.do_work"})
      },
      overrides
    )
  end

  describe "POST /api/v1/jobs — enabled field" do
    test "omitting enabled defaults to enabled" do
      conn = post(api_conn(), ~p"/api/v1/jobs", valid_job_params())
      resp = json_response(conn, 201)

      assert resp["enabled"] == true
    end

    test "enabled: true creates an enabled job" do
      conn = post(api_conn(), ~p"/api/v1/jobs", valid_job_params(%{"enabled" => true}))
      resp = json_response(conn, 201)

      assert resp["enabled"] == true
    end

    test "enabled: false creates a disabled job (false must not be overwritten)" do
      conn = post(api_conn(), ~p"/api/v1/jobs", valid_job_params(%{"enabled" => false}))
      resp = json_response(conn, 201)

      assert resp["enabled"] == false

      {:ok, job} = ScheduledJobs.get_job(resp["id"])
      assert job.enabled == false
    end
  end
end
