defmodule EyeInTheSky.Canvases do
  @moduledoc false
  import Ecto.Query

  alias EyeInTheSky.Repo
  alias EyeInTheSky.Canvases.{Canvas, CanvasSession}

  def list_canvases do
    Repo.all(from c in Canvas, order_by: [asc: c.inserted_at])
  end

  def get_canvas(id) do
    case Repo.get(Canvas, id) do
      nil -> {:error, :not_found}
      canvas -> {:ok, canvas}
    end
  end

  def get_canvas!(id), do: Repo.get!(Canvas, id)

  def create_canvas(attrs) do
    %Canvas{}
    |> Canvas.changeset(attrs)
    |> Repo.insert()
  end

  def delete_canvas(id) do
    case Repo.get(Canvas, id) do
      nil -> {:error, :not_found}
      canvas -> Repo.delete(canvas)
    end
  end

  def list_canvas_sessions(canvas_id) do
    Repo.all(
      from cs in CanvasSession,
        where: cs.canvas_id == ^canvas_id,
        order_by: [asc: cs.inserted_at]
    )
  end

  # on_conflict: {:replace, [:updated_at]} ensures the returned struct always
  # has a real id (not nil), even when the row already exists.
  def add_session(canvas_id, session_id) do
    %CanvasSession{}
    |> CanvasSession.changeset(%{canvas_id: canvas_id, session_id: session_id})
    |> Repo.insert(
      on_conflict: {:replace, [:updated_at]},
      conflict_target: [:canvas_id, :session_id],
      returning: true
    )
  end

  def remove_session(canvas_id, session_id) do
    {_n, _} =
      from(cs in CanvasSession,
        where: cs.canvas_id == ^canvas_id and cs.session_id == ^session_id
      )
      |> Repo.delete_all()

    :ok
  end

  def update_window_layout(canvas_session_id, attrs) do
    case Repo.get(CanvasSession, canvas_session_id) do
      nil -> {:error, :not_found}
      cs -> cs |> CanvasSession.changeset(attrs) |> Repo.update()
    end
  end
end
