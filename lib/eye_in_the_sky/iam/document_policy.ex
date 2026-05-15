defmodule EyeInTheSky.IAM.DocumentPolicy do
  @moduledoc """
  Schema for `iam_document_policies`.

  Join table linking a policy document to an IAM policy.
  The row is first-class (carries its own timestamps) rather than a bare
  many_to_many so it can gain position, added_by, etc. in future phases.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EyeInTheSky.IAM.{PolicyDocument, Policy}

  schema "iam_document_policies" do
    belongs_to :document, PolicyDocument
    belongs_to :policy, Policy

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "Changeset for attaching a policy to a document."
  def changeset(dp \\ %__MODULE__{}, attrs) do
    dp
    |> cast(attrs, [:document_id, :policy_id])
    |> validate_required([:document_id, :policy_id])
    |> foreign_key_constraint(:document_id)
    |> foreign_key_constraint(:policy_id)
    |> unique_constraint([:document_id, :policy_id],
      name: :iam_document_policies_unique,
      message: "policy already in document"
    )
  end
end
