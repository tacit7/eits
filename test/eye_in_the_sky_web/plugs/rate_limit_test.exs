defmodule EyeInTheSkyWeb.Plugs.RateLimitTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias EyeInTheSkyWeb.Plugs.RateLimit

  # Tests run against the running RateLimiter ETS backend. Use a distinct IP
  # per test so buckets don't bleed across runs.

  setup do
    # Ensure a fresh bucket per test by using a unique remote IP.
    ip = {127, 0, 0, :rand.uniform(250) + 1}
    {:ok, ip: ip}
  end

  defp build_conn(ip, headers \\ []) do
    conn = conn(:get, "/api/v1/some/endpoint") |> Map.put(:remote_ip, ip)
    Enum.reduce(headers, conn, fn {k, v}, acc -> Plug.Conn.put_req_header(acc, k, v) end)
  end

  test "no default and no matching rule is a no-op", %{ip: ip} do
    conn = build_conn(ip) |> RateLimit.call([])
    refute conn.halted
  end

  test "default limit allows up to N requests, then 429s", %{ip: ip} do
    opts = [default: {3, :timer.minutes(1)}]

    for _ <- 1..3 do
      conn = build_conn(ip) |> RateLimit.call(opts)
      refute conn.halted
    end

    conn = build_conn(ip) |> RateLimit.call(opts)
    assert conn.halted
    assert conn.status == 429
  end

  test "orchestrator header gets the multiplier bump", %{ip: ip} do
    opts = [default: {3, :timer.minutes(1)}]

    # 3 * 5 = 15 should be allowed for orchestrators
    for _ <- 1..15 do
      conn =
        build_conn(ip, [{"x-eits-role", "orchestrator"}])
        |> RateLimit.call(opts)

      refute conn.halted
    end

    conn =
      build_conn(ip, [{"x-eits-role", "orchestrator"}])
      |> RateLimit.call(opts)

    assert conn.halted
    assert conn.status == 429
  end

  test "orchestrator bucket is separate from the regular IP bucket", %{ip: ip} do
    opts = [default: {2, :timer.minutes(1)}]

    # Use up the regular bucket
    for _ <- 1..2 do
      conn = build_conn(ip) |> RateLimit.call(opts)
      refute conn.halted
    end

    # Regular bucket is now exhausted
    conn = build_conn(ip) |> RateLimit.call(opts)
    assert conn.halted

    # Orchestrator bucket should still be fresh (separate key)
    conn =
      build_conn(ip, [{"x-eits-role", "orchestrator"}])
      |> RateLimit.call(opts)

    refute conn.halted
  end

end
