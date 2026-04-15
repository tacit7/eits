defmodule EyeInTheSkyWeb.WellKnownController do
  use EyeInTheSkyWeb, :controller

  @doc """
  GET /.well-known/webauthn

  Returns related origins metadata for passkey/WebAuthn related-origin checks.
  Must be served as application/json.
  """
  def webauthn(conn, _params) do
    primary_origin = Application.get_env(:wax_, :origin)
    extra_origins = Application.get_env(:eye_in_the_sky, :webauthn_extra_origins, [])

    origins =
      [primary_origin | extra_origins]
      |> Enum.filter(&is_binary/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    json(conn, %{origins: origins})
  end
end
