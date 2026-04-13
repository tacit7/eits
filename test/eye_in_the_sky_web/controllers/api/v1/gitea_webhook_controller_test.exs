defmodule EyeInTheSkyWeb.Api.V1.GiteaWebhookControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  # sanitize_branch/1 and sanitize_text/1 tests moved to:
  # test/eye_in_the_sky/agents/webhook_sanitizer_test.exs

  # Signature verification is bypassed in test via allow_unsigned_webhooks.
  # Set up the application env before tests run.
  setup do
    Application.put_env(:eye_in_the_sky, :allow_unsigned_webhooks, true)
    Application.put_env(:eye_in_the_sky, :gitea_webhook_secret, "")
    Application.put_env(:eye_in_the_sky, :project_path, "/tmp/test-project")
    on_exit(fn ->
      Application.delete_env(:eye_in_the_sky, :allow_unsigned_webhooks)
      Application.delete_env(:eye_in_the_sky, :gitea_webhook_secret)
      Application.delete_env(:eye_in_the_sky, :project_path)
    end)
    :ok
  end

  defp pr_payload(action) do
    %{
      "action" => action,
      "pull_request" => %{
        "number" => 1,
        "title" => "Test PR",
        "body" => "Session-ID: 00000000-0000-0000-0000-000000000000",
        "html_url" => "http://localhost:3000/claude/eits-web/pulls/1",
        "head" => %{"ref" => "feature-branch"}
      },
      "repository" => %{"full_name" => "claude/eits-web"}
    }
  end

  defp post_webhook(conn, payload, event \\ "pull_request") do
    conn
    |> put_req_header("x-gitea-event", event)
    |> put_req_header("content-type", "application/json")
    |> assign(:raw_body, Jason.encode!(payload))
    |> post(~p"/api/v1/webhooks/gitea", payload)
  end

  describe "action=opened" do
    test "spawns codex reviewer and returns 200", %{conn: conn} do
      Process.put(:mock_agent_manager_response, {:ok, :create_session})

      conn = post_webhook(conn, pr_payload("opened"))

      assert %{"success" => true, "message" => "Codex reviewer spawned"} =
               json_response(conn, 200)
    end

    test "returns 500 when agent spawn fails", %{conn: conn} do
      Process.put(:mock_agent_manager_response, {:error, :spawn_failed})

      conn = post_webhook(conn, pr_payload("opened"))

      assert %{"error" => _} = json_response(conn, 500)
    end
  end

  describe "action=synchronize" do
    test "spawns codex reviewer and returns 200", %{conn: conn} do
      Process.put(:mock_agent_manager_response, {:ok, :create_session})

      conn = post_webhook(conn, pr_payload("synchronize"))

      assert %{"success" => true, "message" => "Codex reviewer spawned"} =
               json_response(conn, 200)
    end

    test "returns 500 when agent spawn fails", %{conn: conn} do
      Process.put(:mock_agent_manager_response, {:error, :spawn_failed})

      conn = post_webhook(conn, pr_payload("synchronize"))

      assert %{"error" => _} = json_response(conn, 500)
    end

    test "returns 401 for invalid signature", %{conn: conn} do
      Application.put_env(:eye_in_the_sky, :allow_unsigned_webhooks, false)
      Application.put_env(:eye_in_the_sky, :gitea_webhook_secret, "secret")

      conn =
        conn
        |> put_req_header("x-gitea-event", "pull_request")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-gitea-signature", "invalidsig")
        |> assign(:raw_body, Jason.encode!(pr_payload("synchronize")))
        |> post(~p"/api/v1/webhooks/gitea", pr_payload("synchronize"))

      assert %{"error" => "Invalid signature"} = json_response(conn, 401)
    end
  end

  describe "non-target actions" do
    test "closed action is ignored without spawning reviewer", %{conn: conn} do
      Process.put(:mock_agent_manager_response, {:error, :should_not_be_called})

      conn = post_webhook(conn, pr_payload("closed"))

      assert %{"success" => true, "message" => "Ignored"} = json_response(conn, 200)
    end

    test "labeled action is ignored without spawning reviewer", %{conn: conn} do
      Process.put(:mock_agent_manager_response, {:error, :should_not_be_called})

      conn = post_webhook(conn, pr_payload("labeled"))

      assert %{"success" => true, "message" => "Ignored"} = json_response(conn, 200)
    end
  end
end
