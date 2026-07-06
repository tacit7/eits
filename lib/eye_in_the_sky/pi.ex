defmodule EyeInTheSky.Pi do
  @moduledoc """
  Pi provider namespace helpers.

  Session transcripts persist under `session_root()/<eits-session-uuid>/`.
  Runtime transcript data must never live in release-bundled priv/.
  """

  @doc """
  Resolution order: EITS_PI_SESSION_ROOT env var, app config
  `:pi_session_root`, then `var/pi-sessions` relative to the app root.
  """
  @spec session_root() :: String.t()
  def session_root do
    System.get_env("EITS_PI_SESSION_ROOT") ||
      Application.get_env(:eye_in_the_sky, :pi_session_root) ||
      Path.expand("var/pi-sessions")
  end

  @doc "Returns (and creates) the transcript directory for a session UUID."
  @spec session_dir(String.t()) :: String.t()
  def session_dir(session_uuid) when is_binary(session_uuid) do
    dir = Path.join(session_root(), session_uuid)
    File.mkdir_p!(dir)
    dir
  end
end
