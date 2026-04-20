defmodule EyeInTheSkyWeb.Api.V1.FallbackController do
  @moduledoc "Action fallback for API v1 controllers. Handles common error tuples."
  use EyeInTheSkyWeb, :controller

  import EyeInTheSkyWeb.ControllerHelpers

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "Not found"})
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Validation failed", details: translate_errors(changeset)})
  end

  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: reason})
  end

  def call(conn, {:error, status, reason}) when is_atom(status) and is_binary(reason) do
    conn
    |> put_status(status)
    |> json(%{error: reason})
  end

  def call(conn, {:error, status}) when is_atom(status) do
    conn
    |> put_status(status)
    |> json(%{error: to_string(status)})
  end

  def call(conn, {:error, _reason}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Internal server error"})
  end
end
