defmodule EyeInTheSky.OrchestratorTimers.Timer do
  @moduledoc "Struct representing an active orchestrator timer."

  defstruct [:token, :timer_ref, :mode, :interval_ms, :message, :started_at, :next_fire_at]
end
