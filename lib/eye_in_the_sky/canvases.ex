defmodule EyeInTheSky.Canvases do
  @moduledoc false
  import Ecto.Query

  alias EyeInTheSky.Repo
  alias EyeInTheSky.Canvases.{Canvas, CanvasSession, CanvasTerminal}

  def list_canvases do
    Repo.all(from c in Canvas, order_by: [asc: c.inserted_at])
  end

  def list_canvases_preloaded do
    Repo.all(from c in Canvas, order_by: [asc: c.inserted_at], preload: :canvas_sessions)
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
    result =
      %CanvasSession{}
      |> CanvasSession.changeset(%{canvas_id: canvas_id, session_id: session_id})
      |> Repo.insert(
        on_conflict: {:replace, [:updated_at]},
        conflict_target: [:canvas_id, :session_id],
        returning: true
      )

    if match?({:ok, _}, result) do
      EyeInTheSky.Events.canvas_session_added(canvas_id)
    end

    result
  end

  def remove_session(canvas_id, session_id) do
    {_n, _} =
      from(cs in CanvasSession,
        where: cs.canvas_id == ^canvas_id and cs.session_id == ^session_id
      )
      |> Repo.delete_all()

    :ok
  end

  def rename_canvas(canvas_id, name) do
    case Repo.get(Canvas, canvas_id) do
      nil -> {:error, :not_found}
      canvas -> canvas |> Canvas.changeset(%{name: name}) |> Repo.update()
    end
  end

  @min_window_dim 100

  def update_window_layout(canvas_session_id, attrs) do
    attrs =
      attrs
      |> maybe_clamp(:width)
      |> maybe_clamp(:height)

    case Repo.get(CanvasSession, canvas_session_id) do
      nil -> {:error, :not_found}
      cs -> cs |> CanvasSession.changeset(attrs) |> Repo.update()
    end
  end

  defp maybe_clamp(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, v} when is_integer(v) and v < @min_window_dim -> Map.put(attrs, key, @min_window_dim)
      _ -> attrs
    end
  end

  def reset_canvas_layout(canvas_id) do
    sessions = list_canvas_sessions(canvas_id)

    if sessions == [] do
      :ok
    else
      # H5 fix: one unnest UPDATE-FROM replaces N individual Repo.update calls.
      # Each row has a different (pos_x, pos_y) computed from its index, so
      # a plain Repo.update_all with a single SET cannot be used.
      {ids, xs, ys} =
        sessions
        |> Enum.with_index()
        |> Enum.reduce({[], [], []}, fn {cs, i}, {id_acc, x_acc, y_acc} ->
          {[cs.id | id_acc], [24 + i * 40 | x_acc], [24 + i * 40 | y_acc]}
        end)

      Repo.query!(
        """
        UPDATE canvas_sessions AS cs
        SET pos_x = v.pos_x,
            pos_y = v.pos_y,
            width = 320,
            height = 260,
            updated_at = NOW()
        FROM unnest($1::bigint[], $2::int[], $3::int[]) AS v(id, pos_x, pos_y)
        WHERE cs.id = v.id
        """,
        [ids, xs, ys]
      )

      :ok
    end
  end

  def count_sessions_per_canvas do
    from(cs in CanvasSession, group_by: cs.canvas_id, select: {cs.canvas_id, count(cs.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  # --- Terminal Windows ---

  def list_terminals(canvas_id) do
    Repo.all(from ct in CanvasTerminal, where: ct.canvas_id == ^canvas_id, order_by: [asc: ct.inserted_at])
  end

  def create_terminal(canvas_id, attrs \\ %{}) do
    %CanvasTerminal{}
    |> CanvasTerminal.changeset(Map.put(attrs, :canvas_id, canvas_id))
    |> Repo.insert()
  end

  def delete_terminal(id) do
    case Repo.get(CanvasTerminal, id) do
      nil -> {:error, :not_found}
      ct -> Repo.delete(ct)
    end
  end

  def update_terminal_layout(id, attrs) do
    case Repo.get(CanvasTerminal, id) do
      nil -> {:error, :not_found}
      ct -> ct |> CanvasTerminal.changeset(attrs) |> Repo.update()
    end
  end
end
