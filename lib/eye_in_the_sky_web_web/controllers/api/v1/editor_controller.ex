defmodule EyeInTheSkyWebWeb.Api.V1.EditorController do
  use EyeInTheSkyWebWeb, :controller

  action_fallback EyeInTheSkyWebWeb.Api.V1.FallbackController

  alias EyeInTheSkyWeb.Settings

  def open(conn, %{"path" => path}) when byte_size(path) > 0 do
    editor = Settings.get("preferred_editor")
    Task.start(fn -> System.cmd(editor, [path], stderr_to_stdout: true) end)
    json(conn, %{ok: true})
  end

  def open(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "path is required"})
  end
end
