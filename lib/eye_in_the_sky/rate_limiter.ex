defmodule EyeInTheSky.RateLimiter do
  use Hammer, backend: :ets
end
