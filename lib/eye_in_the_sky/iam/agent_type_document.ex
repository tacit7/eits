defmodule EyeInTheSky.IAM.AgentTypeDocument do
  @moduledoc """
  Schema for `iam_agent_type_documents`.

  Attaches a policy document to a concrete agent type string.
  The wildcard `"*"` is explicitly rejected — documents are attached to
  specific agent types, not the global pool.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EyeInTheSky.IAM.PolicyDocument

  schema "iam_agent_type_documents" do
    field :agent_type, :string
    belongs_to :document, PolicyDocument

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "Changeset for attaching a document to an agent type."
  def changeset(atd \\ %__MODULE__{}, attrs) do
    atd
    |> cast(attrs, [:agent_type, :document_id])
    |> update_change(:agent_type, &String.trim/1)
    |> validate_required([:agent_type, :document_id])
    |> validate_length(:agent_type, min: 1, max: 255)
    |> validate_exclusion(:agent_type, ["*"], message: "cannot be wildcard")
    |> foreign_key_constraint(:document_id)
    |> unique_constraint([:agent_type, :document_id],
      name: :iam_agent_type_documents_unique,
      message: "document already attached to this agent type"
    )
  end
end
