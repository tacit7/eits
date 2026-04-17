defmodule EyeInTheSky.IAM.Policy do
  @moduledoc """
  Ecto schema for an IAM policy record.

  A policy matches incoming hook contexts on four axes — `agent_type`,
  `project` (FK preferred, path glob fallback), `action` (tool name), and
  optional `resource_glob` over the resource path. An optional `condition`
  JSONB predicate adds runtime gating (time, env, session state).

  Effects:

    * `"allow"` — grants permission when this is the highest-priority
      non-denied match.
    * `"deny"`  — blocks the tool call outright; wins over all allows.
    * `"instruct"` — accumulates advisory output attached to the final
      decision regardless of permission. Not an authorization outcome.

  Built-in policies carry a stable `system_key` and a list of
  `editable_fields` — matcher fields are locked on system policies; operators
  can only tune behavioral fields like `enabled`, `priority`, `condition`,
  `message`.

  Note on writes: all mutations must go through the `EyeInTheSky.IAM` context
  boundary so the `PolicyCache` stays consistent. Direct `Repo` writes are
  disallowed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EyeInTheSky.Projects.Project

  @effects ~w(allow deny instruct)
  @supported_condition_predicates ~w(time_between env_equals session_state_equals)

  @type t :: %__MODULE__{
          id: integer() | nil,
          system_key: String.t() | nil,
          name: String.t(),
          effect: String.t(),
          agent_type: String.t(),
          project_id: integer() | nil,
          project_path: String.t() | nil,
          action: String.t(),
          resource_glob: String.t() | nil,
          condition: map(),
          priority: integer(),
          enabled: boolean(),
          message: String.t() | nil,
          editable_fields: [String.t()]
        }

  schema "iam_policies" do
    field :system_key, :string
    field :name, :string
    field :effect, :string
    field :agent_type, :string, default: "*"
    field :project_path, :string, default: "*"
    field :action, :string, default: "*"
    field :resource_glob, :string
    field :condition, :map, default: %{}
    field :priority, :integer, default: 0
    field :enabled, :boolean, default: true
    field :message, :string
    field :editable_fields, {:array, :string}, default: []

    belongs_to :project, Project

    timestamps(type: :utc_datetime_usec)
  end

  @create_fields ~w(
    system_key name effect agent_type project_id project_path action
    resource_glob condition priority enabled message editable_fields
  )a

  @required_fields ~w(name effect)a

  @doc "Changeset for creating a new policy (user or built-in)."
  @spec create_changeset(t() | map(), map()) :: Ecto.Changeset.t()
  def create_changeset(policy \\ %__MODULE__{}, attrs) do
    policy
    |> cast(attrs, @create_fields, empty_values: [])
    |> validate_required(@required_fields)
    |> validate_inclusion(:effect, @effects)
    |> validate_glob_or_wildcard(:project_path)
    |> validate_glob_or_wildcard(:resource_glob)
    |> validate_condition()
    |> foreign_key_constraint(:project_id)
    |> unique_constraint(:system_key, name: :iam_policies_system_key_unique_index)
  end

  @doc """
  Changeset for updating an existing policy. On system policies
  (`system_key` non-nil), only fields listed in `editable_fields` may change.
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(%__MODULE__{} = policy, attrs) do
    policy
    |> cast(attrs, @create_fields, empty_values: [])
    |> validate_required(@required_fields)
    |> validate_inclusion(:effect, @effects)
    |> validate_glob_or_wildcard(:project_path)
    |> validate_glob_or_wildcard(:resource_glob)
    |> validate_condition()
    |> enforce_locked_fields(policy)
    |> foreign_key_constraint(:project_id)
    |> unique_constraint(:system_key, name: :iam_policies_system_key_unique_index)
  end

  # ── validators ──────────────────────────────────────────────────────────────

  @doc false
  def supported_condition_predicates, do: @supported_condition_predicates

  defp validate_glob_or_wildcard(changeset, field) do
    case get_field(changeset, field) do
      nil ->
        changeset

      "" ->
        add_error(changeset, field, "must not be empty; use \"*\" for wildcard")

      value when is_binary(value) ->
        # Glob syntax is permissive (`*`, `?`, `[…]`, `/`); here we just
        # forbid obviously broken patterns. Real matching uses
        # `EyeInTheSky.IAM.Matcher` which will be introduced in Phase 2.
        if Regex.match?(~r/[\x00-\x1f]/, value) do
          add_error(changeset, field, "contains control characters")
        else
          changeset
        end

      _ ->
        add_error(changeset, field, "must be a string")
    end
  end

  defp validate_condition(changeset) do
    case get_field(changeset, :condition) do
      nil ->
        put_change(changeset, :condition, %{})

      cond_map when is_map(cond_map) ->
        Enum.reduce(cond_map, changeset, fn {key, value}, cs ->
          validate_condition_entry(cs, to_string(key), value)
        end)

      _ ->
        add_error(changeset, :condition, "must be a map")
    end
  end

  defp validate_condition_entry(cs, key, value) do
    cond do
      key not in @supported_condition_predicates ->
        add_error(cs, :condition, "unsupported predicate: #{key}")

      key == "time_between" ->
        validate_time_between(cs, value)

      key == "env_equals" ->
        validate_env_equals(cs, value)

      key == "session_state_equals" ->
        validate_string(cs, :condition, value, "session_state_equals expects a string")
    end
  end

  defp validate_time_between(cs, [from, to])
       when is_binary(from) and is_binary(to) do
    if time_string?(from) and time_string?(to) do
      cs
    else
      add_error(cs, :condition, "time_between expects [HH:MM, HH:MM] 24h strings")
    end
  end

  defp validate_time_between(cs, _) do
    add_error(cs, :condition, "time_between expects a two-element list [from, to]")
  end

  defp validate_env_equals(cs, %{} = map) do
    Enum.reduce(map, cs, fn
      {k, v}, acc when is_binary(k) and is_binary(v) -> acc
      _, acc -> add_error(acc, :condition, "env_equals expects string => string map")
    end)
  end

  defp validate_env_equals(cs, _),
    do: add_error(cs, :condition, "env_equals expects a map of string => string")

  defp validate_string(cs, _field, v, _msg) when is_binary(v), do: cs
  defp validate_string(cs, field, _v, msg), do: add_error(cs, field, msg)

  defp time_string?(str) do
    Regex.match?(~r/\A([01]\d|2[0-3]):[0-5]\d\z/, str)
  end

  defp enforce_locked_fields(changeset, %__MODULE__{system_key: nil}), do: changeset

  defp enforce_locked_fields(changeset, %__MODULE__{editable_fields: editable}) do
    locked = Enum.map(@create_fields, &Atom.to_string/1) -- (editable ++ ["editable_fields"])

    Enum.reduce(locked, changeset, fn field_str, cs ->
      field = String.to_existing_atom(field_str)

      case fetch_change(cs, field) do
        {:ok, _} ->
          add_error(cs, field, "is locked on this system policy")

        :error ->
          cs
      end
    end)
  end
end
