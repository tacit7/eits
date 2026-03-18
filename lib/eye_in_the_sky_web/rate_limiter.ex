defmodule EyeInTheSkyWeb.RateLimiter do
  use Hammer, backend: :ets
end
