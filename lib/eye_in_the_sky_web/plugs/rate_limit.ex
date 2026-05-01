defmodule EyeInTheSkyWeb.Plugs.RateLimit do
  @moduledoc """
  Rate limiting using Hammer v7.

  Specific rules per remote IP for WebAuthn endpoints:
    - login/challenge:    10 attempts / 1 minute  (username enumeration)
    - login/complete:      5 attempts / 5 minutes  (brute force)
    - register/challenge:  5 attempts / 1 hour     (registration abuse)
    - register/complete:   5 attempts / 1 hour

  A default rate limit can be configured via opts:
    plug EyeInTheSkyWeb.Plugs.RateLimit, default: {60, :timer.minutes(1)}

  When a `default` is set, any request not matching a specific rule falls back
  to the default limit keyed on `"api:<ip>"`.

  ## Orchestrator bump (Phase 1)

  Requests that send the `x-eits-role: orchestrator` header get a 5× higher
  burst ceiling on the default bucket (keyed separately as
  `"api:orch:<ip>"` so orchestrator traffic does not consume the regular IP
  bucket and vice versa). Specific rules (auth) are unaffected.

  ## Per-session bucket (Phase 2, feature-flagged)

  When the `rate_limit_per_session` setting is `true` AND the request includes
  a valid `x-eits-session: <uuid>` header that matches an existing session row,
  the bucket key becomes `"api:sess:<uuid>"` with generous limits (600 req/min,
  60 req per 10s burst) so co-located actors on the same IP don't starve each
  other. If the flag is off, the header is missing, or the session UUID is
  unknown, the plug falls back to the Phase 1 behavior above.

  Each evaluation emits a `[:eits, :rate_limit, :check]` telemetry event with
  the final bucket name, optional session id, and :allowed | :throttled status.
  """

  import Plug.Conn

  @rules %{
    ["auth", "login", "challenge"] => {10, :timer.minutes(1)},
    ["auth", "login", "complete"] => {5, :timer.minutes(5)},
    ["auth", "register", "challenge"] => {5, :timer.hours(1)},
    ["auth", "register", "complete"] => {5, :timer.hours(1)}
  }

  @orchestrator_multiplier 5

  # Per-session limits: 600 req/min sustained, 60 req per 10s burst.
  # Plug evaluates the 10s burst; the minute budget is implicit (6 * 60 = 360 < 600).
  @session_burst_limit 60
  @session_burst_scale 10_000

  def init(opts), do: opts

  def call(conn, opts) do
    if Application.get_env(:eye_in_the_sky, :rate_limit_enabled, true) == false do
      conn
    else
      do_call(conn, opts)
    end
  end

  defp do_call(conn, opts) do
    rule = Map.get(@rules, conn.path_info)
    default = Keyword.get(opts, :default)

    cond do
      rule ->
        {limit, scale} = rule
        action = List.last(conn.path_info)
        ip = ip_string(conn)
        check(conn, "auth:#{action}:#{ip}", limit, scale, %{bucket_kind: :auth, session_id: nil})

      default == nil ->
        conn

      true ->
        apply_default(conn, default)
    end
  end

  defp apply_default(conn, default) do
    case per_session_bucket(conn) do
      {:ok, uuid, session_id} ->
        check(
          conn,
          "api:sess:#{uuid}",
          @session_burst_limit,
          @session_burst_scale,
          %{bucket_kind: :session, session_id: session_id}
        )

      :fallback ->
        fallback_default(conn, default)
    end
  end

  defp fallback_default(conn, {limit, scale}) do
    if orchestrator?(conn) do
      ip = ip_string(conn)

      check(
        conn,
        "api:orch:#{ip}",
        limit * @orchestrator_multiplier,
        scale,
        %{bucket_kind: :orchestrator, session_id: nil}
      )
    else
      ip = ip_string(conn)
      check(conn, "api:#{ip}", limit, scale, %{bucket_kind: :ip, session_id: nil})
    end
  end

  defp check(conn, key, limit, scale, meta) do
    case EyeInTheSky.RateLimiter.hit(key, scale, limit) do
      {:allow, count} ->
        emit_telemetry(:allowed, key, limit, max(limit - count, 0), meta)
        conn

      {:deny, _retry_after} ->
        emit_telemetry(:throttled, key, limit, 0, meta)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(429, ~s({"error":"too many requests"}))
        |> halt()
    end
  end

  defp emit_telemetry(status, bucket, limit, remaining, meta) do
    :telemetry.execute(
      [:eits, :rate_limit, :check],
      %{remaining: remaining, limit: limit},
      Map.merge(meta, %{bucket: bucket, status: status})
    )
  end

  defp per_session_bucket(conn) do
    with true <- EyeInTheSky.Settings.get_boolean("rate_limit_per_session"),
         [raw | _] <- get_req_header(conn, "x-eits-session"),
         uuid when is_binary(uuid) <- normalize_uuid(raw),
         {:ok, session_id} <- lookup_session_id(uuid) do
      {:ok, uuid, session_id}
    else
      _ -> :fallback
    end
  end

  defp normalize_uuid(raw) do
    trimmed = String.trim(raw)

    if byte_size(trimmed) == 36 and trimmed =~ ~r/^[0-9a-fA-F-]{36}$/ do
      String.downcase(trimmed)
    else
      nil
    end
  end

  defp lookup_session_id(uuid) do
    EyeInTheSky.Sessions.get_session_id_by_uuid(uuid)
  end

  defp ip_string(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  defp orchestrator?(conn) do
    case get_req_header(conn, "x-eits-role") do
      ["orchestrator" | _] -> true
      _ -> false
    end
  end
end
