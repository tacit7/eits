defmodule EyeInTheSkyWeb.CspHeaderTest do
  use ExUnit.Case
  import Plug.Test

  describe "CSP nonce assignment via plug" do
    test "CspNonce plug assigns nonce to conn" do
      conn = conn(:get, "/")
      conn = EyeInTheSkyWeb.Plugs.CspNonce.call(conn, [])

      assert nonce = conn.assigns[:csp_nonce]
      assert is_binary(nonce)
      assert byte_size(nonce) > 0
    end

    test "each request gets a unique nonce" do
      conn1 = conn(:get, "/") |> EyeInTheSkyWeb.Plugs.CspNonce.call([])
      conn2 = conn(:get, "/") |> EyeInTheSkyWeb.Plugs.CspNonce.call([])

      assert conn1.assigns[:csp_nonce] != conn2.assigns[:csp_nonce]
    end
  end
end
