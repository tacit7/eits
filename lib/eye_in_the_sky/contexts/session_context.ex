defmodule EyeInTheSky.Contexts.SessionContext do
  use Ecto.Schema
  import Ecto.Changeset

  schema "session_context" do
    field :context, :string

    belongs_to :agent, EyeInTheSky.Agents.Agent, type: :integer
    # Note: session_id is not a foreign key in the schema, just a field
    field :session_id, :integer

    field :created_at, :string
    field :updated_at, :string
  end

  @doc false
  def changeset(session_context, attrs) do
    session_context
    |> cast(attrs, [:agent_id, :session_id, :context])
    |> validate_required([:agent_id, :session_id, :context])
  end
end
