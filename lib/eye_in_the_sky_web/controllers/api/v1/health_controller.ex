defmodule EyeInTheSkyWeb.Api.V1.HealthController do
  use EyeInTheSkyWeb, :controller

  def index(conn, _params) do
    json(conn, %{ok: true, status: "healthy"})
  end
end
