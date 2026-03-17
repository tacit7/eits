defmodule EyeInTheSkyWebWeb.Api.V1.EditorController do
  use EyeInTheSkyWebWeb, :controller

  action_fallback EyeInTheSkyWebWeb.Api.V1.FallbackController

  alias EyeInTheSkyWeb.Settings

  @allowed_editors ["code", "vim", "nvim", "nano", "emacs", "cursor", "zed"]

  def open(conn, %{"path" => path}) when byte_size(path) > 0 do
    editor = Settings.get("preferred_editor")
    allowed_prefix =
      Application.get_env(:eye_in_the_sky_web, :allowed_path_prefix, System.user_home!())

    expanded = Path.expand(path)

    cond do
      editor not in @allowed_editors ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "editor not allowed"})

      not String.starts_with?(expanded, allowed_prefix) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "path outside allowed prefix"})

      true ->
        Task.start(fn -> System.cmd(editor, [expanded], stderr_to_stdout: true) end)
        json(conn, %{ok: true})
    end
  end

  def open(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "path is required"})
  end
end
