defmodule EyeInTheSkyWeb.Logs.Log do
  use Ecto.Schema
  import Ecto.Changeset

  schema "logs" do
    field :type, :string
    field :message, :string
    field :timestamp, :string

    belongs_to :session, EyeInTheSkyWeb.Sessions.Session, type: :integer
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [:session_id, :type, :message, :timestamp])
    |> validate_required([:session_id, :type, :message, :timestamp])
  end
end
