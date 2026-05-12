defmodule EyeInTheSky.Github.WebhookRuleExecution do
  use Ecto.Schema
  import Ecto.Changeset

  schema "github_webhook_rule_executions" do
    field :rule_id, :integer
    field :delivery_id, :string
    field :repository_full_name, :string
    field :pr_number, :integer
    field :status, :string
    field :result, :map
    field :error_message, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(exec, attrs) do
    exec
    |> cast(attrs, [
      :rule_id,
      :delivery_id,
      :repository_full_name,
      :pr_number,
      :status,
      :result,
      :error_message
    ])
    |> validate_required([:rule_id, :delivery_id, :status])
    |> validate_inclusion(:status, ~w[ok failed skipped])
  end
end
