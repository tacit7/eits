defmodule EyeInTheSkyWeb.Repo do
  use Ecto.Repo,
    otp_app: :eye_in_the_sky_web,
    adapter: Ecto.Adapters.Postgres
end
