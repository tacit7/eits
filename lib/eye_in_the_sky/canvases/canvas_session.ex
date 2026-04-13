defmodule EyeInTheSky.Canvases.CanvasSession do
  use Ecto.Schema
  import Ecto.Changeset

  schema "canvas_sessions" do
    belongs_to :canvas, EyeInTheSky.Canvases.Canvas
    # Bare integer field — FK to sessions.id (integer PK, not UUID).
    # No belongs_to :session to keep Canvases context decoupled from Sessions context.
    field :session_id, :integer
    field :pos_x, :integer, default: 0
    field :pos_y, :integer, default: 0
    field :width, :integer, default: 320
    field :height, :integer, default: 260
    timestamps()
  end

  def changeset(cs, attrs) do
    cs
    |> cast(attrs, [:canvas_id, :session_id, :pos_x, :pos_y, :width, :height])
    |> validate_required([:canvas_id, :session_id])
    |> unique_constraint([:canvas_id, :session_id])
  end
end
