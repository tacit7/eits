defmodule EyeInTheSkyWeb.Api.V1.GithubWebhookControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Events

  @secret "test_webhook_secret"
  @payload ~s({"action":"opened","pull_request":{"id":1,"number":1,"head":{"ref":"main"},"base":{"ref":"main"},"labels":[],"draft":false,"merged":false},"sender":{"login":"uriel"},"repository":{"full_name":"tacit7/eits"}})

  setup do
    Application.put_env(:eye_in_the_sky, :github_webhook_secret, @secret)
    on_exit(fn -> Application.delete_env(:eye_in_the_sky, :github_webhook_secret) end)
    :ok
  end

  defp sign(body),
    do:
      "sha256=" <> (:crypto.mac(:hmac, :sha256, @secret, body) |> Base.encode16(case: :lower))

  defp post_webhook(conn, body, opts \\ []) do
    sig = Keyword.get(opts, :signature, sign(body))
    event = Keyword.get(opts, :event, "pull_request")
    delivery = Keyword.get(opts, :delivery, "test-delivery-#{:rand.uniform(999_999)}")

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-hub-signature-256", sig)
    |> put_req_header("x-github-event", event)
    |> put_req_header("x-github-delivery", delivery)
    |> post("/api/v1/webhooks/github", body)
  end

  test "returns 202 for valid webhook", %{conn: conn} do
    Events.subscribe_github_webhook()
    conn = post_webhook(conn, @payload)
    assert conn.status == 202

    assert_receive {:github_webhook_received, _delivery_id}, 500
  end

  test "returns 401 for bad HMAC", %{conn: conn} do
    conn = post_webhook(conn, @payload, signature: "sha256=" <> String.duplicate("a", 64))
    assert conn.status == 401
  end

  test "returns 401 for missing signature", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-github-event", "pull_request")
      |> put_req_header("x-github-delivery", "test-delivery-1")
      |> post("/api/v1/webhooks/github", @payload)

    assert conn.status == 401
  end

  test "returns 400 for missing X-GitHub-Event", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-hub-signature-256", sign(@payload))
      |> put_req_header("x-github-delivery", "test-delivery-2")
      |> post("/api/v1/webhooks/github", @payload)

    assert conn.status == 400
  end

  test "returns 400 for missing X-GitHub-Delivery", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-hub-signature-256", sign(@payload))
      |> put_req_header("x-github-event", "pull_request")
      |> post("/api/v1/webhooks/github", @payload)

    assert conn.status == 400
  end

  test "returns 202 for duplicate delivery_id (no reprocessing)", %{conn: conn} do
    delivery = "fixed-delivery-id"
    post_webhook(conn, @payload, delivery: delivery)
    conn2 = build_conn()
    conn2 = post_webhook(conn2, @payload, delivery: delivery)
    assert conn2.status == 202
  end
end
