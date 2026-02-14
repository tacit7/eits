defmodule EyeInTheSkyWeb.Logs.SessionLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "session_logs" do
    field :session_id, :integer
    field :level, :string
    field :category, :string
    field :message, :string
    field :details, :string
    field :created_at, :string

    belongs_to :session, EyeInTheSkyWeb.ExecutionAgents.ExecutionAgent,
      define_field: false,
      foreign_key: :session_id,
      type: :integer
  end

  @doc false
  def changeset(session_log, attrs) do
    session_log
    |> cast(attrs, [:session_id, :level, :category, :message, :details])
    |> validate_required([:session_id, :level, :category, :message])
  end
end
