defmodule EyeInTheSky.Canvases.Canvas do
  use Ecto.Schema
  import Ecto.Changeset

  schema "canvases" do
    field :name, :string
    has_many :canvas_sessions, EyeInTheSky.Canvases.CanvasSession
    timestamps()
  end

  def changeset(canvas, attrs) do
    canvas
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
  end
end
