defmodule EyeInTheSky.IAM.PolicyDocument do
  @moduledoc """
  Schema for `iam_policy_documents`.

  A policy document is a named, reusable collection of policies.
  Documents can be attached to agent type strings so that every agent
  of that type evaluates the document's policies in addition to the
  global policy pool.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EyeInTheSky.IAM.{AgentTypeDocument, DocumentPolicy}

  schema "iam_policy_documents" do
    field :name, :string
    field :description, :string

    has_many :document_policies, DocumentPolicy,
      foreign_key: :document_id,
      on_replace: :delete

    has_many :policies, through: [:document_policies, :policy]

    has_many :agent_type_documents, AgentTypeDocument,
      foreign_key: :document_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Changeset for creating a new policy document."
  def create_changeset(doc \\ %__MODULE__{}, attrs) do
    doc
    |> cast(attrs, [:name, :description])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint(:name,
      name: :iam_policy_documents_name_ci_unique,
      message: "already exists (case-insensitive)"
    )
  end

  @doc "Changeset for updating an existing policy document. Delegates to `create_changeset/2`."
  def update_changeset(doc, attrs), do: create_changeset(doc, attrs)
end
