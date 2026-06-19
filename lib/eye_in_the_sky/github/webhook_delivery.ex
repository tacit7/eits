defmodule EyeInTheSky.Github.WebhookDelivery do
  use Ecto.Schema
  import Ecto.Changeset

  schema "github_webhook_deliveries" do
    field :delivery_id, :string
    field :hook_id, :string
    field :event_type, :string
    field :event_header, :string
    field :action, :string
    field :repository_full_name, :string
    field :sender_login, :string
    field :pr_number, :integer
    field :head_branch, :string
    field :base_branch, :string
    field :payload, :map
    field :status, :string, default: "pending"
    field :error_message, :string
    field :processing_started_at, :utc_datetime_usec
    field :processed_at, :utc_datetime_usec
    field :attempt_count, :integer, default: 0
    field :max_attempts, :integer, default: 5
    field :duplicate_count, :integer, default: 0
    field :last_duplicate_at, :utc_datetime_usec
    field :received_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :delivery_id,
      :hook_id,
      :event_type,
      :event_header,
      :action,
      :repository_full_name,
      :sender_login,
      :pr_number,
      :head_branch,
      :base_branch,
      :payload,
      :status,
      :error_message,
      :processing_started_at,
      :processed_at,
      :attempt_count,
      :max_attempts,
      :duplicate_count,
      :last_duplicate_at,
      :received_at
    ])
    |> validate_required([:delivery_id, :event_type, :event_header, :received_at])
    |> unique_constraint(:delivery_id)
  end
end
