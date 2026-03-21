defmodule EyeInTheSky.Repo do
  use Ecto.Repo,
    otp_app: :eye_in_the_sky,
    adapter: Ecto.Adapters.Postgres
end
