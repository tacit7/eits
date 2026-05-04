defmodule EyeInTheSky.Settings.Schema do
  @moduledoc """
  Single source of truth for DM settings: dotted-key → metadata
  (type, default, scopes where the key is allowed).

  Defaults are derived from this map; the UI-validation allowlist is too.
  Adding a new setting requires touching this module only.

  ## Type tags

    * `:boolean`
    * `:float_or_nil`
    * `:integer_or_nil`
    * `:string_or_nil`
    * `{:enum, [allowed]}` — value must be one of the listed strings
    * `{:enum_or_nil, [allowed]}` — same, but `nil`/`""` collapse to `nil`

  ## Scopes

    * `:agent` — key may be persisted on `agents.settings`
    * `:session` — key may be persisted on `sessions.settings`

  Most keys are valid in both scopes.
  """

  @schema %{
    # ---- general -----------------------------------------------------------
    "general.max_budget_usd" => %{
      type: :float_or_nil,
      default: nil,
      namespace: "general",
      scopes: [:agent, :session]
    },
    "general.show_live_stream" => %{
      type: :boolean,
      default: true,
      namespace: "general",
      scopes: [:agent, :session]
    },
    "general.thinking_enabled" => %{
      type: :boolean,
      default: false,
      namespace: "general",
      scopes: [:agent, :session]
    },
    "general.notify_on_stop" => %{
      type: :boolean,
      default: false,
      namespace: "general",
      scopes: [:agent, :session]
    },

    # ---- anthropic / claude flags -----------------------------------------
    "anthropic.permission_mode" => %{
      type: {:enum, ["default", "acceptEdits", "plan", "bypassPermissions"]},
      default: "acceptEdits",
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.max_turns" => %{
      type: :integer_or_nil,
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.fallback_model" => %{
      type: {:enum_or_nil, ["opus", "sonnet", "haiku"]},
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.from_pr" => %{
      type: :string_or_nil,
      default: nil,
      namespace: "anthropic",
      scopes: [:session]
    },
    "anthropic.json_schema" => %{
      type: :string_or_nil,
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.allowed_tools" => %{
      type: :string_or_nil,
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.permission_prompt_tool" => %{
      type: :string_or_nil,
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.add_dir" => %{
      type: :string_or_nil,
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.mcp_config" => %{
      type: :string_or_nil,
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.plugin_dir" => %{
      type: :string_or_nil,
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.settings_file" => %{
      type: :string_or_nil,
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.agents_json" => %{
      type: :string_or_nil,
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.agent_persona" => %{
      type: :string_or_nil,
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.system_prompt" => %{
      type: :string_or_nil,
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.system_prompt_file" => %{
      type: :string_or_nil,
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.append_system_prompt" => %{
      type: :string_or_nil,
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.append_system_prompt_file" => %{
      type: :string_or_nil,
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.debug_categories" => %{
      type: :string_or_nil,
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.bare" => %{
      type: :boolean,
      default: false,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.verbose" => %{
      type: :boolean,
      default: false,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.include_partial_messages" => %{
      type: :boolean,
      default: false,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.no_session_persistence" => %{
      type: :boolean,
      default: false,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.chrome" => %{
      type: {:enum_or_nil, ["on", "off"]},
      default: nil,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.sandbox" => %{
      type: :boolean,
      default: false,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },
    "anthropic.dangerously_skip_permissions" => %{
      type: :boolean,
      default: false,
      namespace: "anthropic",
      scopes: [:agent, :session]
    },

    # ---- openai / codex flags ---------------------------------------------
    "openai.ask_for_approval" => %{
      type: {:enum, ["never", "on-failure", "on-request", "untrusted"]},
      default: "never",
      namespace: "openai",
      scopes: [:agent, :session]
    },
    "openai.sandbox" => %{
      type: {:enum, ["read-only", "workspace-write", "danger-full-access"]},
      default: "workspace-write",
      namespace: "openai",
      scopes: [:agent, :session]
    },
    "openai.full_auto" => %{
      type: :boolean,
      default: false,
      namespace: "openai",
      scopes: [:agent, :session]
    },
    "openai.dangerously_bypass_approvals_and_sandbox" => %{
      type: :boolean,
      default: false,
      namespace: "openai",
      scopes: [:agent, :session]
    }
  }

  @doc """
  Full map of dotted-key → spec. Build-time constant.
  """
  @spec all() :: %{required(String.t()) => map()}
  def all, do: @schema

  @doc "Look up a single key's metadata. Returns `{:ok, spec}` or `{:error, :unknown_setting_key}`."
  @spec fetch(String.t()) :: {:ok, map()} | {:error, :unknown_setting_key}
  def fetch(key) when is_binary(key) do
    case Map.fetch(@schema, key) do
      {:ok, spec} -> {:ok, spec}
      :error -> {:error, :unknown_setting_key}
    end
  end

  @doc "True if the dotted key exists in the schema."
  @spec known?(String.t()) :: boolean()
  def known?(key), do: Map.has_key?(@schema, key)

  @doc """
  Defaults map, derived from the schema. Nested by namespace:
      %{"general" => %{"max_budget_usd" => nil, ...}, "anthropic" => ...}
  """
  @spec defaults() :: map()
  def defaults do
    @schema
    |> Enum.reduce(%{}, fn {dotted_key, spec}, acc ->
      [_namespace, _leaf] = parts = String.split(dotted_key, ".", parts: 2)

      put_in_path(acc, parts, spec.default)
    end)
  end

  defp put_in_path(map, [head], value), do: Map.put(map, head, value)

  defp put_in_path(map, [head | rest], value) do
    sub = Map.get(map, head, %{})
    Map.put(map, head, put_in_path(sub, rest, value))
  end
end
