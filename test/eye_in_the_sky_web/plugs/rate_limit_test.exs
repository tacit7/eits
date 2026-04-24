defmodule EyeInTheSkyWeb.Plugs.RateLimitTest do
  use EyeInTheSky.DataCase, async: false
  import Plug.Test

  alias EyeInTheSky.Factory
  alias EyeInTheSky.Settings
  alias EyeInTheSkyWeb.Plugs.RateLimit

  # Tests run against the running RateLimiter ETS backend. Use a distinct IP
  # per test so buckets don't bleed across runs.

  setup tags do
    ip = {127, 0, 0, :rand.uniform(250) + 1}

    # Set the Phase 2 flag unless the test opts out.
    if tags[:per_session] do
      Settings.put("rate_limit_per_session", "true")
      on_exit(fn -> Settings.put("rate_limit_per_session", "false") end)
    end

    ref = attach_telemetry()
    on_exit(fn -> :telemetry.detach(ref) end)

    {:ok, ip: ip, telemetry_ref: ref}
  end

  defp build_conn(ip, headers \\ []) do
    conn = conn(:get, "/api/v1/some/endpoint") |> Map.put(:remote_ip, ip)
    Enum.reduce(headers, conn, fn {k, v}, acc -> Plug.Conn.put_req_header(acc, k, v) end)
  end

  defp attach_telemetry do
    ref = make_ref()
    test_pid = self()

    :telemetry.attach(
      {__MODULE__, ref},
      [:eits, :rate_limit, :check],
      fn event, measurements, metadata, _ ->
        send(test_pid, {:telemetry, ref, event, measurements, metadata})
      end,
      nil
    )

    ref
  end

  describe "feature flag off (default)" do
    test "no default and no matching rule is a no-op", %{ip: ip} do
      conn = build_conn(ip) |> RateLimit.call([])
      refute conn.halted
    end

    test "default limit allows up to N requests, then 429s", %{ip: ip, telemetry_ref: ref} do
      opts = [default: {3, :timer.minutes(1)}]

      for _ <- 1..3 do
        conn = build_conn(ip) |> RateLimit.call(opts)
        refute conn.halted
      end

      conn = build_conn(ip) |> RateLimit.call(opts)
      assert conn.halted
      assert conn.status == 429

      # Telemetry should have fired at least once; drain and assert one throttle.
      assert Enum.any?(drain_telemetry(ref), fn {_m, md} -> md.status == :throttled end)
    end

    test "orchestrator header gets the multiplier bump", %{ip: ip} do
      opts = [default: {3, :timer.minutes(1)}]

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

      for _ <- 1..2 do
        conn = build_conn(ip) |> RateLimit.call(opts)
        refute conn.halted
      end

      conn = build_conn(ip) |> RateLimit.call(opts)
      assert conn.halted

      conn =
        build_conn(ip, [{"x-eits-role", "orchestrator"}])
        |> RateLimit.call(opts)

      refute conn.halted
    end

    test "x-eits-session header is ignored when flag is off", %{ip: ip, telemetry_ref: ref} do
      opts = [default: {2, :timer.minutes(1)}]
      session = Factory.new_session()

      for _ <- 1..2 do
        conn =
          build_conn(ip, [{"x-eits-session", session.uuid}])
          |> RateLimit.call(opts)

        refute conn.halted
      end

      # Should have hit the IP bucket (now exhausted)
      conn =
        build_conn(ip, [{"x-eits-session", session.uuid}])
        |> RateLimit.call(opts)

      assert conn.halted

      # All telemetry should report ip bucket kind, never :session.
      events = drain_telemetry(ref)
      assert Enum.all?(events, fn {_m, md} -> md.bucket_kind == :ip end)
    end
  end

  describe "feature flag on" do
    @describetag :per_session

    test "per-session bucket activates with valid session header", %{
      ip: ip,
      telemetry_ref: ref
    } do
      opts = [default: {3, :timer.minutes(1)}]
      session = Factory.new_session()
      headers = [{"x-eits-session", session.uuid}]

      # Session bucket allows 60 req / 10s burst — fire 60 allowed, 61st denied.
      for _ <- 1..60 do
        conn = build_conn(ip, headers) |> RateLimit.call(opts)
        refute conn.halted
      end

      conn = build_conn(ip, headers) |> RateLimit.call(opts)
      assert conn.halted
      assert conn.status == 429

      # Regular IP bucket should still be fresh (not consumed by session hits).
      conn2 = build_conn(ip) |> RateLimit.call(opts)
      refute conn2.halted

      events = drain_telemetry(ref)

      session_events = Enum.filter(events, fn {_m, md} -> md.bucket_kind == :session end)
      assert length(session_events) >= 60

      Enum.each(session_events, fn {_m, md} ->
        assert md.session_id == session.id
        assert md.bucket == "api:sess:" <> session.uuid
      end)

      assert Enum.any?(session_events, fn {_m, md} -> md.status == :throttled end)
    end

    test "missing x-eits-session header falls back to IP bucket", %{
      ip: ip,
      telemetry_ref: ref
    } do
      opts = [default: {2, :timer.minutes(1)}]

      for _ <- 1..2 do
        conn = build_conn(ip) |> RateLimit.call(opts)
        refute conn.halted
      end

      conn = build_conn(ip) |> RateLimit.call(opts)
      assert conn.halted

      events = drain_telemetry(ref)
      assert Enum.all?(events, fn {_m, md} -> md.bucket_kind == :ip end)
    end

    test "unknown session uuid falls back to IP bucket", %{ip: ip, telemetry_ref: ref} do
      opts = [default: {2, :timer.minutes(1)}]
      bogus = Ecto.UUID.generate()
      headers = [{"x-eits-session", bogus}]

      for _ <- 1..2 do
        conn = build_conn(ip, headers) |> RateLimit.call(opts)
        refute conn.halted
      end

      conn = build_conn(ip, headers) |> RateLimit.call(opts)
      assert conn.halted

      events = drain_telemetry(ref)
      assert Enum.all?(events, fn {_m, md} -> md.bucket_kind == :ip end)
    end
  end

  defp drain_telemetry(ref, acc \\ []) do
    receive do
      {:telemetry, ^ref, _event, measurements, metadata} ->
        drain_telemetry(ref, [{measurements, metadata} | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end
end
