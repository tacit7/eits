defmodule EyeInTheSkyWebWeb.DevController do
  @moduledoc """
  Dev-only controller for test helpers. Only reachable when dev_routes is enabled.
  """
  use EyeInTheSkyWebWeb, :controller

  alias EyeInTheSkyWeb.Accounts

  @doc """
  GET /dev/test-login?user_id=<id>

  Sets the session user_id without WebAuthn. Dev/test only.
  Redirects to the path specified by `redirect_to` param, or `/` by default.
  """
  def test_login(conn, %{"user_id" => user_id_str} = params) do
    user_id = String.to_integer(user_id_str)

    case Accounts.get_user(user_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> text("User #{user_id} not found")

      _user ->
        redirect_to = Map.get(params, "redirect_to", "/")

        conn
        |> put_session(:user_id, user_id)
        |> redirect(to: redirect_to)
    end
  end

  def test_login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> text("user_id param required")
  end
end
