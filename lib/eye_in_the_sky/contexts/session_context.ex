defmodule EyeInTheSky.Contexts.SessionContext do
  use Ecto.Schema
  import Ecto.Changeset

  schema "session_context" do
    field :context, :string
    field :metadata, :map, default: %{}

    belongs_to :agent, EyeInTheSky.Agents.Agent, type: :integer
    # Note: session_id is not a foreign key in the schema, just a field
    field :session_id, :integer

    field :created_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end

  @doc false
  def changeset(session_context, attrs) do
    session_context
    |> cast(attrs, [:agent_id, :session_id, :context, :metadata])
    |> validate_required([:agent_id, :session_id, :context])
  end
end
