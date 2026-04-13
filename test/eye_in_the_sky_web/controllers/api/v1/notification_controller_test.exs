defmodule EyeInTheSkyWeb.Api.V1.NotificationControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Accounts.ApiKey
  alias EyeInTheSky.Notifications.Notification
  alias EyeInTheSkyWeb.ControllerHelpers

  defp uniq, do: System.unique_integer([:positive])

  setup %{conn: _conn} do
    token = "test_api_key_#{uniq()}"
    {:ok, _} = ApiKey.create(token, "test")
    conn = Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
    {:ok, conn: conn}
  end

  describe "POST /api/v1/notifications" do
    test "creates a notification with valid params", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/notifications", %{"title" => "Test #{uniq()}"})
      resp = json_response(conn, 200)
      assert resp["success"] == true
      assert resp["id"]
    end

    test "returns 400 when title is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/notifications", %{})
      resp = json_response(conn, 400)
      assert resp["success"] == false
      assert resp["message"] =~ "title is required"
    end

    test "returns 400 when title is empty string", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/notifications", %{"title" => ""})
      resp = json_response(conn, 400)
      assert resp["success"] == false
    end
  end

  # Unit tests for the changeset error sanitization fix.
  #
  # The controller's {:error, cs} branch cannot be reached via the HTTP API because
  # Notifications.notify/2 normalizes invalid categories to "system" before the
  # changeset runs, and the controller already guards against nil/empty titles.
  # These tests verify the fix directly: translate_errors/1 is used instead of
  # inspect(cs.errors), so no raw changeset internals are exposed.
  describe "changeset error sanitization (unit)" do
    test "translate_errors/1 returns a map, not a raw inspect string" do
      # Force an invalid changeset: missing title + invalid category
      cs = Notification.changeset(%Notification{}, %{title: nil, category: "invalid_cat"})
      refute cs.valid?

      errors = ControllerHelpers.translate_errors(cs)

      assert is_map(errors)
      # Must not contain inspect-style Elixir term output
      errors_json = Jason.encode!(errors)
      refute errors_json =~ ~r/\[\{.*,.*\{.*\}\}\]/
      refute errors_json =~ "#Ecto"
    end

    test "translate_errors/1 returns human-readable field errors" do
      cs = Notification.changeset(%Notification{}, %{title: nil, category: "invalid_cat"})
      errors = ControllerHelpers.translate_errors(cs)

      # Should have field-keyed entries
      assert Map.has_key?(errors, :title) or Map.has_key?(errors, :category)
      # Each value should be a list of strings
      Enum.each(errors, fn {_field, messages} ->
        assert is_list(messages)
        assert Enum.all?(messages, &is_binary/1)
      end)
    end
  end
end
