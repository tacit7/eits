defmodule EyeInTheSky.RateLimiter do
  @moduledoc false
  use Hammer, backend: :ets
end
