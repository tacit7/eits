defmodule EyeInTheSky.ModelEntry do
  @moduledoc """
  Unified model metadata for the shared model selector (spec §4.1,
  docs/superpowers/specs/2026-07-08-model-selector-design.md).

  `provider` is carried explicitly on every entry rather than inferred from
  section context. `premium?` marks incremental-cost rows shown with a `$`
  badge — it does not mean "this is the only model that costs money."
  """

  defstruct [
    :provider,
    :slug,
    :label,
    :group,
    :sub_provider,
    premium?: false,
    legacy?: false,
    default?: false
  ]

  @type t :: %__MODULE__{
          provider: String.t(),
          slug: String.t(),
          label: String.t(),
          group: String.t(),
          sub_provider: String.t() | nil,
          premium?: boolean(),
          legacy?: boolean(),
          default?: boolean()
        }
end
