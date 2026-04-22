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

  ## Orchestrator bump

  Requests that send the `x-eits-role: orchestrator` header get a 5× higher
  burst ceiling on the default bucket (keyed separately as
  `"api:orch:<ip>"` so orchestrator traffic does not consume the regular IP
  bucket and vice versa). Specific rules (auth) are unaffected.
  """

  import Plug.Conn

  @rules %{
    ["auth", "login", "challenge"] => {10, :timer.minutes(1)},
    ["auth", "login", "complete"] => {5, :timer.minutes(5)},
    ["auth", "register", "challenge"] => {5, :timer.hours(1)},
    ["auth", "register", "complete"] => {5, :timer.hours(1)}
  }

  @orchestrator_multiplier 5

  def init(opts), do: opts

  def call(conn, opts) do
    rule = Map.get(@rules, conn.path_info)
    default = Keyword.get(opts, :default)
    orchestrator? = rule == nil and orchestrator?(conn)

    effective =
      case rule || default do
        nil -> nil
        {limit, scale} when orchestrator? -> {limit * @orchestrator_multiplier, scale}
        other -> other
      end

    case effective do
      nil ->
        conn

      {limit, scale} ->
        ip = conn.remote_ip |> :inet.ntoa() |> to_string()

        key =
          cond do
            rule ->
              action = List.last(conn.path_info)
              "auth:#{action}:#{ip}"

            orchestrator? ->
              "api:orch:#{ip}"

            true ->
              "api:#{ip}"
          end

        case EyeInTheSky.RateLimiter.hit(key, scale, limit) do
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

  defp orchestrator?(conn) do
    case get_req_header(conn, "x-eits-role") do
      ["orchestrator" | _] -> true
      _ -> false
    end
  end
end
