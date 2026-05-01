defmodule EyeInTheSky.Contexts.AgentContext do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "agent_context" do
    field :context, :string
    field :updated_at, :utc_datetime

    belongs_to :agent, EyeInTheSky.Agents.Agent, primary_key: true, type: :integer
    belongs_to :session, EyeInTheSky.Sessions.Session, primary_key: true, type: :integer
    belongs_to :project, EyeInTheSky.Projects.Project, primary_key: true
  end

  @doc false
  def changeset(agent_context, attrs) do
    agent_context
    |> cast(attrs, [:agent_id, :project_id, :context, :updated_at])
    |> validate_required([:agent_id, :project_id, :context])
    |> unique_constraint([:agent_id, :project_id],
      name: :agent_context_agent_id_project_id_index
    )
  end
end
