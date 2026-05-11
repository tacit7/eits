defmodule EyeInTheSky.Github.WebhookRule do
  use Ecto.Schema
  import Ecto.Changeset

  alias EyeInTheSky.Github.Template

  @action_types ~w[spawn_agent create_task dm_session broadcast_only]
  @required_config %{
    "spawn_agent" => ~w[agent instructions],
    "create_task" => ~w[title],
    "dm_session" => ~w[session_id message],
    "broadcast_only" => ~w[topic message]
  }

  schema "github_webhook_rules" do
    field :event_type, :string
    field :repository_full_name, :string
    field :project_id, :integer
    field :branch_glob, :string
    field :target_branch_glob, :string
    field :action_type, :string
    field :action_config, :map, default: %{}
    field :guard_config, :map, default: %{}
    field :enabled, :boolean, default: true
    field :priority, :integer, default: 100

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :event_type, :repository_full_name, :project_id, :branch_glob,
      :target_branch_glob, :action_type, :action_config, :guard_config,
      :enabled, :priority
    ])
    |> validate_required([:event_type, :action_type, :action_config])
    |> validate_inclusion(:action_type, @action_types)
    |> validate_action_config()
    |> validate_guard_config()
  end

  defp validate_action_config(%{valid?: false} = cs), do: cs

  defp validate_action_config(changeset) do
    action_type = get_field(changeset, :action_type)
    config = get_field(changeset, :action_config) || %{}
    required = Map.get(@required_config, action_type, [])

    with :ok <- check_required_keys(config, required),
         :ok <- validate_templates(config) do
      changeset
    else
      {:error, msg} -> add_error(changeset, :action_config, msg)
    end
  end

  defp check_required_keys(config, required) do
    missing = Enum.reject(required, &Map.has_key?(config, &1))
    if missing == [], do: :ok, else: {:error, "missing required keys: #{Enum.join(missing, ", ")}"}
  end

  defp validate_templates(config) do
    config
    |> Map.values()
    |> Enum.filter(&is_binary/1)
    |> Enum.reduce_while(:ok, fn val, :ok ->
      case Template.validate(val) do
        :ok -> {:cont, :ok}
        {:error, msg} -> {:halt, {:error, msg}}
      end
    end)
  end

  defp validate_guard_config(%{valid?: false} = cs), do: cs

  defp validate_guard_config(changeset) do
    config = get_field(changeset, :guard_config) || %{}
    allowed = ~w[once_per_pr max_runs_per_pr ignore_drafts only_if_label]
    unknown = Map.keys(config) -- allowed

    if unknown == [] do
      changeset
    else
      add_error(changeset, :guard_config, "unknown guard keys: #{Enum.join(unknown, ", ")}")
    end
  end
end
