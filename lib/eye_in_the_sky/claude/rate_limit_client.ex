defmodule EyeInTheSky.Claude.RateLimitClient do
  @moduledoc """
  Fetches Anthropic rate-limit utilization via the OAuth usage API.

  Reads Claude Code credentials from the macOS Keychain (or
  `~/.claude/.credentials.json` on Linux) and calls
  `https://api.anthropic.com/api/oauth/usage`.

  Results are cached in-process:
    - Success  → 5-minute TTL
    - Error    → 2-minute backoff
  """

  use Agent

  require Logger

  @cache_ttl_ms 5 * 60 * 1000
  @error_ttl_ms 2 * 60 * 1000
  @api_url "https://api.anthropic.com/api/oauth/usage"
  @credential_service "Claude Code-credentials"
  @credentials_file "~/.claude/.credentials.json"

  # ── Supervision ───────────────────────────────────────────────────────────

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Returns `{:ok, data}` or `{:error, reason}`.
  `data` is a map with keys `:five_hour`, `:seven_day`, `:seven_day_sonnet`,
  `:extra_usage`. Each rate-limit entry has `:utilization` (float 0-100) and
  `:resets_at` (ISO8601 string or nil). `extra_usage` has `:is_enabled`,
  `:monthly_limit`, `:used_credits`, `:currency`.
  """
  @spec fetch() :: {:ok, map()} | {:error, atom()}
  def fetch do
    now = System.monotonic_time(:millisecond)

    case Agent.get(__MODULE__, & &1) do
      %{ok?: true, result: result, fetched_at: t} when now - t < @cache_ttl_ms ->
        {:ok, result}

      %{ok?: false, fetched_at: t} when now - t < @error_ttl_ms ->
        {:error, :cached_error}

      _ ->
        refresh_cache(now)
    end
  end

  @doc "Bypass the cache and immediately re-fetch from the Anthropic API."
  @spec force_refresh() :: {:ok, map()} | {:error, atom()}
  def force_refresh do
    Agent.update(__MODULE__, fn _ -> %{} end)
    refresh_cache(System.monotonic_time(:millisecond))
  end

  # ── Internal ──────────────────────────────────────────────────────────────

  defp refresh_cache(now) do
    case load() do
      {:ok, data} ->
        Agent.update(__MODULE__, fn _ -> %{ok?: true, result: data, fetched_at: now} end)
        {:ok, data}

      {:error, reason} ->
        Agent.update(__MODULE__, fn _ -> %{ok?: false, fetched_at: now, reason: reason} end)
        {:error, reason}
    end
  end

  defp load do
    with {:ok, creds} <- read_credentials(),
         {:ok, token} <- extract_token(creds),
         {:ok, body} <- call_api(token) do
      {:ok, parse_response(body)}
    end
  end

  # Try macOS Keychain first, fall back to ~/.claude/.credentials.json.
  defp read_credentials do
    case read_from_keychain() do
      {:ok, creds} -> {:ok, creds}
      _ -> read_from_file()
    end
  end

  defp read_from_keychain do
    case System.cmd("security", ["find-generic-password", "-s", @credential_service, "-w"],
           stderr_to_stdout: false
         ) do
      {json, 0} -> parse_credentials_json(String.trim(json))
      _ -> {:error, :keychain_not_found}
    end
  end

  defp read_from_file do
    path = Path.expand(@credentials_file)

    case File.read(path) do
      {:ok, json} -> parse_credentials_json(json)
      {:error, :enoent} -> {:error, :no_credentials}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_credentials_json(json) do
    case Jason.decode(json) do
      {:ok, %{"claudeAiOauth" => oauth}} when is_map(oauth) -> {:ok, oauth}
      {:ok, _} -> {:error, :missing_oauth_key}
      {:error, _} -> {:error, :invalid_credentials_json}
    end
  end

  defp extract_token(%{"accessToken" => token, "expiresAt" => expires_at_ms})
       when is_binary(token) and is_integer(expires_at_ms) do
    now_ms = System.system_time(:millisecond)

    if expires_at_ms <= now_ms do
      Logger.warning("RateLimitClient: Claude OAuth token expired; re-authenticate via Claude CLI")
      {:error, :token_expired}
    else
      {:ok, token}
    end
  end

  defp extract_token(%{"accessToken" => token}) when is_binary(token), do: {:ok, token}
  defp extract_token(_), do: {:error, :missing_access_token}

  defp call_api(token) do
    url = @api_url

    headers = [
      {"authorization", "Bearer #{token}"},
      {"anthropic-beta", "oauth-2025-04-20"}
    ]

    case Req.get(url, headers: headers, receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("RateLimitClient: HTTP error: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_response(body) do
    %{
      five_hour: parse_rate(body["five_hour"]),
      seven_day: parse_rate(body["seven_day"]),
      seven_day_sonnet: parse_rate(body["seven_day_sonnet"]),
      extra_usage: parse_extra(body["extra_usage"])
    }
  end

  defp parse_rate(nil), do: nil

  defp parse_rate(%{"utilization" => util, "resets_at" => resets_at}) do
    %{utilization: util, resets_at: resets_at}
  end

  defp parse_extra(nil), do: nil

  defp parse_extra(%{} = extra) do
    %{
      is_enabled: Map.get(extra, "is_enabled", false),
      monthly_limit: Map.get(extra, "monthly_limit"),
      used_credits: Map.get(extra, "used_credits", 0.0),
      currency: Map.get(extra, "currency", "USD")
    }
  end
end
