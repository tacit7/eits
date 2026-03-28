defmodule EyeInTheSkyWeb.TelemetryDispatch do
  @moduledoc """
  Stable MFA target for telemetry_poller.

  telemetry_poller permanently removes measurements that raise. Registering
  EyeInTheSkyWeb.Telemetry directly means a hot-reload undef removes it for
  good. This module never changes, so it's always available. It delegates to
  Telemetry with a rescue so the poller never sees a failure.
  """

  def dispatch do
    EyeInTheSkyWeb.Telemetry.dispatch_measurements()
  rescue
    _ -> :ok
  end
end
