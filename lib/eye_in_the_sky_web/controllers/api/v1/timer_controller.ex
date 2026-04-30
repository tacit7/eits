defmodule EyeInTheSkyWeb.Api.V1.TimerController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  alias EyeInTheSky.OrchestratorTimers
  alias EyeInTheSky.Utils.ToolHelpers

  @presets_ms %{
    "5m" => 5 * 60 * 1_000,
    "10m" => 10 * 60 * 1_000,
    "15m" => 15 * 60 * 1_000,
    "30m" => 30 * 60 * 1_000,
    "1h" => 60 * 60 * 1_000
  }

  @doc """
  GET /api/v1/sessions/:session_id/timer

  Returns the active timer for a session, or 404 if none.
  """
  def show(conn, %{"session_id" => session_id}) do
    with {:ok, int_id} <- resolve_session(session_id) do
      case OrchestratorTimers.get_timer(int_id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "no active timer for this session"})

        timer ->
          json(conn, %{success: true, timer: present_timer(timer)})
      end
    end
  end

  @doc """
  POST /api/v1/sessions/:session_id/timer

  Schedule a timer that will deliver a message to the target session when it fires.
  Replaces any existing timer for that session.

  Body (one of delay_ms or preset is required):
    - mode:     "once" (default) | "repeating"
    - delay_ms: integer milliseconds (>= 100)
    - preset:   "5m" | "10m" | "15m" | "30m" | "1h"
    - message:  string — defaults to the standard check-in prompt

  delay_ms takes precedence over preset if both are supplied.
  """
  def schedule(conn, %{"session_id" => session_id} = params) do
    with {:ok, int_id} <- resolve_session(session_id),
         {:ok, delay_ms} <- resolve_delay(params),
         {:ok, mode} <- resolve_mode(params) do
      message =
        case params["message"] do
          m when is_binary(m) ->
            case String.trim(m) do
              "" -> OrchestratorTimers.default_message()
              trimmed -> trimmed
            end

          _ ->
            OrchestratorTimers.default_message()
        end

      result =
        case mode do
          :once -> OrchestratorTimers.schedule_once(int_id, delay_ms, message)
          :repeating -> OrchestratorTimers.schedule_repeating(int_id, delay_ms, message)
        end

      case result do
        {:ok, action} ->
          timer = OrchestratorTimers.get_timer(int_id)

          conn
          |> put_status(:created)
          |> json(%{
            success: true,
            action: to_string(action),
            timer: present_timer(timer)
          })

        {:error, {:invalid_interval, msg}} ->
          {:error, :bad_request, msg}

        {:error, reason} ->
          {:error, :internal_server_error, inspect(reason)}
      end
    end
  end

  @doc """
  DELETE /api/v1/sessions/:session_id/timer

  Cancel the active timer for a session. No-op (200) if none active.
  """
  def cancel(conn, %{"session_id" => session_id}) do
    with {:ok, int_id} <- resolve_session(session_id) do
      case OrchestratorTimers.cancel(int_id) do
        {:ok, :cancelled} -> json(conn, %{success: true, message: "timer cancelled"})
        {:ok, :noop} -> json(conn, %{success: true, message: "no active timer"})
      end
    end
  end

  # --- helpers ---

  # Wraps ToolHelpers.resolve_session_int_id and maps its bare string errors to
  # proper {:error, :not_found, msg} tuples so FallbackController returns 404.
  defp resolve_session(session_id) do
    case ToolHelpers.resolve_session_int_id(session_id) do
      {:ok, int_id} -> {:ok, int_id}
      {:error, msg} when is_binary(msg) -> {:error, :not_found, msg}
    end
  end

  defp resolve_delay(%{"delay_ms" => raw}) when is_integer(raw), do: validate_delay(raw)

  defp resolve_delay(%{"delay_ms" => raw}) when is_binary(raw) do
    case ToolHelpers.parse_int(raw) do
      nil -> {:error, :bad_request, "delay_ms must be an integer"}
      n -> validate_delay(n)
    end
  end

  defp resolve_delay(%{"preset" => preset}) do
    case Map.fetch(@presets_ms, preset) do
      {:ok, ms} ->
        {:ok, ms}

      :error ->
        valid = @presets_ms |> Map.keys() |> Enum.join(", ")
        {:error, :bad_request, "unknown preset '#{preset}'; valid: #{valid}"}
    end
  end

  defp resolve_delay(_), do: {:error, :bad_request, "delay_ms or preset is required"}

  defp validate_delay(ms) when is_integer(ms) and ms >= 100, do: {:ok, ms}
  defp validate_delay(ms), do: {:error, :bad_request, "delay_ms must be >= 100, got #{ms}"}

  defp resolve_mode(%{"mode" => "repeating"}), do: {:ok, :repeating}
  defp resolve_mode(%{"mode" => "once"}), do: {:ok, :once}

  defp resolve_mode(%{"mode" => other}),
    do: {:error, :bad_request, "unknown mode '#{other}'; valid: once, repeating"}

  defp resolve_mode(_), do: {:ok, :once}

  defp present_timer(nil), do: nil

  defp present_timer(timer) do
    %{
      mode: timer.mode,
      interval_ms: timer.interval_ms,
      message: timer.message,
      started_at: timer.started_at,
      next_fire_at: timer.next_fire_at
    }
  end
end
