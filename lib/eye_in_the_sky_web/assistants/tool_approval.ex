defmodule EyeInTheSkyWeb.Assistants.ToolApproval do
  @moduledoc """
  Schema for tool approval requests.
  When an assistant requests a tool that requires_approval, a record is created here
  and execution is blocked until a human approves or denies it.
  Maps to the "tool_approvals" database table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  @valid_statuses ~w(pending approved denied expired)

  schema "tool_approvals" do
    field :tool_name, :string
    field :payload, :map, default: %{}
    field :status, :string, default: "pending"
    field :requested_by_type, :string
    field :requested_by_id, :string
    field :reviewed_by_id, :integer
    field :reviewed_at, :naive_datetime
    field :expires_at, :naive_datetime
    field :inserted_at, :naive_datetime
    field :updated_at, :naive_datetime

    belongs_to :session, EyeInTheSkyWeb.Sessions.Session
    belongs_to :assistant, EyeInTheSkyWeb.Assistants.Assistant
  end

  @doc false
  def changeset(approval, attrs) do
    approval
    |> cast(attrs, [
      :session_id,
      :assistant_id,
      :tool_name,
      :payload,
      :status,
      :requested_by_type,
      :requested_by_id,
      :reviewed_by_id,
      :reviewed_at,
      :expires_at
    ])
    |> validate_required([:session_id, :tool_name])
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:assistant_id)
  end
end
