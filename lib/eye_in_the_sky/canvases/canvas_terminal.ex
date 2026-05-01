defmodule EyeInTheSky.Canvases.CanvasTerminal do
  use Ecto.Schema
  import Ecto.Changeset

  schema "canvas_terminals" do
    belongs_to :canvas, EyeInTheSky.Canvases.Canvas
    field :pos_x, :integer, default: 0
    field :pos_y, :integer, default: 0
    field :width, :integer, default: 620
    field :height, :integer, default: 400

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(ct, attrs) do
    ct
    |> cast(attrs, [:canvas_id, :pos_x, :pos_y, :width, :height])
    |> validate_required([:canvas_id])
  end
end
