defmodule EyeInTheSkyWeb.WellKnownControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  test "GET /.well-known/webauthn returns JSON origins", %{conn: conn} do
    conn = get(conn, "/.well-known/webauthn")

    assert get_resp_header(conn, "content-type")
           |> Enum.any?(&String.starts_with?(&1, "application/json"))

    body = json_response(conn, 200)
    assert is_list(body["origins"])
    assert body["origins"] != []
  end
end
