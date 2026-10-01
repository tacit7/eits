defmodule EyeInTheSky.PiModelDiscoveryStub do
  @moduledoc false

  # UI mounts can enqueue discovery after the test that created them has ended.
  # Keep default discovery independent of real harnesses and temporary CLI stubs.
  def discover_models, do: {:ok, []}
end
