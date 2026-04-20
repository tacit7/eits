defmodule EyeInTheSkyWeb.Plugs.CspNonceTest do
  use ExUnit.Case
  import Plug.Test

  alias EyeInTheSkyWeb.Plugs.CspNonce

  test "generates and assigns a nonce" do
    conn = conn(:get, "/") |> CspNonce.call([])

    assert nonce = conn.assigns[:csp_nonce]
    assert is_binary(nonce)
    assert byte_size(nonce) > 0
  end

  test "generates different nonces for different requests" do
    conn1 = conn(:get, "/") |> CspNonce.call([])
    conn2 = conn(:get, "/") |> CspNonce.call([])

    nonce1 = conn1.assigns[:csp_nonce]
    nonce2 = conn2.assigns[:csp_nonce]

    assert nonce1 != nonce2
  end
end
