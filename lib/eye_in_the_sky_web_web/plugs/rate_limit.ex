defmodule EyeInTheSkyWebWeb.Plugs.RateLimit do
  @moduledoc """
  Rate limiting for WebAuthn auth endpoints using Hammer v7.

  Limits per remote IP:
    - login/challenge:    10 attempts / 1 minute  (username enumeration)
    - login/complete:      5 attempts / 5 minutes  (brute force)
    - register/challenge:  5 attempts / 1 hour     (registration abuse)
    - register/complete:   5 attempts / 1 hour
  """

  import Plug.Conn

  @rules %{
    ["auth", "login", "challenge"]    => {10, :timer.minutes(1)},
    ["auth", "login", "complete"]     => {5, :timer.minutes(5)},
    ["auth", "register", "challenge"] => {5, :timer.hours(1)},
    ["auth", "register", "complete"]  => {5, :timer.hours(1)}
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    case Map.get(@rules, conn.path_info) do
      nil ->
        conn

      {limit, scale} ->
        ip = conn.remote_ip |> :inet.ntoa() |> to_string()
        action = List.last(conn.path_info)
        key = "auth:#{action}:#{ip}"

        case EyeInTheSkyWeb.RateLimiter.hit(key, scale, limit) do
          {:allow, _count} ->
            conn

          {:deny, _retry_after} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(429, ~s({"error":"too many requests"}))
            |> halt()
        end
    end
  end
end
