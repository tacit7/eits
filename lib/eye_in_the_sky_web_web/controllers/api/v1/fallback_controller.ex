defmodule EyeInTheSkyWebWeb.Api.V1.FallbackController do
  @moduledoc "Action fallback for API v1 controllers. Handles common error tuples."
  use EyeInTheSkyWebWeb, :controller

  import EyeInTheSkyWebWeb.ControllerHelpers

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
end
