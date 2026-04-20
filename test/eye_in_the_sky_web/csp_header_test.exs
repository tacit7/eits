defmodule EyeInTheSkyWeb.CspHeaderTest do
  use EyeInTheSkyWeb.ConnCase

  describe "CSP header" do
    test "script-src includes nonce and not unsafe-inline", %{conn: conn} do
      conn = get(conn, ~p"/auth/login")
      csp = get_resp_header(conn, "content-security-policy") |> List.first()

      assert csp, "CSP header missing"

      script_src = Regex.run(~r/script-src[^;]+/, csp) |> List.first()
      assert script_src, "script-src directive missing"
      assert String.contains?(script_src, "'nonce-"), "nonce not in script-src"
      refute String.contains?(script_src, "'unsafe-inline'"),
             "unsafe-inline still present in script-src"
    end

    test "rendered HTML includes nonce on inline script" do
      # Use a fresh unauthenticated conn to get a 200 from the login page
      conn = Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{})
      conn = get(conn, ~p"/auth/login")
      body = html_response(conn, 200)

      nonce = Regex.run(~r/nonce="([^"]+)"/, body, capture: :all_but_first) |> List.first()
      assert nonce, "no nonce attribute found on script tag in HTML"

      csp = get_resp_header(conn, "content-security-policy") |> List.first()
      assert String.contains?(csp, "'nonce-#{nonce}'"),
             "CSP header nonce does not match HTML script nonce"
    end
  end
end
