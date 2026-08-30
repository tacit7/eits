defmodule EyeInTheSkyWeb.Components.ModelSelector do
  @moduledoc """
  Shared searchable, grouped model-picker popover (spec §5,
  docs/superpowers/specs/2026-07-08-model-selector-design.md). Used
  identically by the DM composer, New Agent drawer, and New Session modal.

  Structure/interactivity split: this component renders the full static
  markup (all rows, all disclosure containers, all data-* attributes); the
  `ModelSelectorPopup` JS hook (assets/js/hooks/model_selector_popup.js)
  owns search filtering, keyboard nav, disclosure toggling, and pushing the
  final selection to the server. The selected provider/model is always
  server-authoritative — the hook never optimistically renders a selection
  the server hasn't confirmed.
  """

  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents, only: [icon: 1]
  alias EyeInTheSkyWeb.Components.DmHelpers
  alias EyeInTheSkyWeb.Helpers.ModelHelpers

  attr :id, :string, required: true
  attr :entries, :list, required: true
  attr :selected_provider, :string, required: true
  attr :selected_model, :string, required: true
  attr :allow_provider_switch?, :boolean, required: true
  attr :event, :string, required: true
  attr :myself, :any, default: nil
  attr :disabled?, :boolean, default: false
  attr :placement, :atom, default: :down

  def model_selector(assigns) do
    entries =
      ModelHelpers.entries_with_current(
        assigns.entries,
        assigns.selected_provider,
        assigns.selected_model
      )

    assigns =
      assigns
      |> assign(:entries, entries)
      |> assign(:sections, group_entries(entries))
      |> assign(:models_json, Jason.encode!(Enum.map(entries, &entry_to_json/1)))

    ~H"""
    <div
      id={@id}
      phx-hook="ModelSelectorPopup"
      phx-target={@myself}
      data-event={@event}
      data-allow-provider-switch={to_string(@allow_provider_switch?)}
      data-selected-provider={@selected_provider}
      data-selected-model={@selected_model}
      data-placement={@placement}
      data-models={@models_json}
      class="relative inline-block"
    >
      <button
        type="button"
        disabled={@disabled?}
        data-selector-trigger
        class="flex h-6 items-center gap-1.5 rounded-box border border-[var(--border-subtle)] bg-base-content/[0.05] px-2 text-mini font-medium text-base-content/55 transition-colors hover:bg-base-content/[0.08] hover:text-base-content/75 focus-ring disabled:cursor-not-allowed disabled:opacity-40"
      >
        <img
          src={DmHelpers.provider_icon(@selected_provider)}
          class={"size-3 flex-shrink-0 #{DmHelpers.provider_icon_class(@selected_provider)}"}
        />
        <span data-selector-trigger-label>{ModelHelpers.model_display_name(@selected_model)}</span>
        <.icon name="hero-chevron-down-mini" class="size-3 flex-shrink-0" />
      </button>

      <div
        data-selector-popover
        class={[
          "hidden absolute z-[1] w-80 rounded-box border border-base-content/8 bg-base-100 shadow-lg",
          if(@placement == :up, do: "bottom-full mb-2", else: "top-full mt-2")
        ]}
      >
        <div class="p-2 border-b border-base-content/8">
          <input
            type="text"
            data-selector-search
            placeholder="Search models..."
            class="w-full bg-transparent border-0 outline-none text-message px-1"
          />
        </div>
        <ul data-selector-list role="listbox" class="max-h-96 overflow-y-auto p-1.5">
          <li :for={{group, group_entries} <- @sections} data-selector-group={group}>
            <div class="menu-title text-mini px-3 pt-2 pb-0.5 text-base-content/40 flex items-center gap-1.5">
              {group}
              <span
                :if={pi_group?(group_entries)}
                class="rounded-full bg-primary/10 px-1.5 py-0.5 text-nano text-primary"
              >
                via Pi
              </span>
            </div>
            <.model_row :for={entry <- group_entries} entry={entry} selected_model={@selected_model} />
          </li>
        </ul>
      </div>
    </div>
    """
  end

  attr :entry, :any, required: true
  attr :selected_model, :string, required: true

  defp model_row(assigns) do
    active = assigns.entry.slug == assigns.selected_model
    assigns = assign(assigns, :active, active)

    ~H"""
    <li
      data-slug={@entry.slug}
      data-provider={@entry.provider}
      data-active={to_string(@active)}
      data-premium={to_string(@entry.premium?)}
      data-legacy={to_string(@entry.legacy?)}
      data-default={to_string(@entry.default?)}
      role="option"
      aria-selected={to_string(@active)}
      class="flex cursor-pointer items-center gap-2 rounded-box px-3 py-2 text-message hover:bg-base-content/[0.04] focus-ring aria-selected:bg-base-content/[0.06]"
    >
      <span class="w-[5px] h-[5px] rounded-full bg-primary/60 flex-shrink-0"></span>
      <span class="flex-1 truncate" data-selector-row-label>{@entry.label}</span>
      <span
        :if={@entry.default?}
        class="rounded-full bg-success/10 px-1.5 py-0.5 text-nano text-success"
      >
        Recommended
      </span>
      <.icon :if={@active} name="hero-check-mini" class="size-3.5 text-primary flex-shrink-0" />
      <.icon
        :if={not @active and @entry.premium?}
        name="hero-currency-dollar-mini"
        class="size-3.5 text-base-content/40 flex-shrink-0"
      />
    </li>
    """
  end

  defp group_entries(entries) do
    entries
    |> Enum.group_by(& &1.group)
    |> Enum.sort_by(fn {group, _} -> group_order(group) end)
  end

  # Fixed section order (spec §5.1): Claude Code, Codex, then Pi sub-provider
  # groups alphabetically, "Current" (synthetic, always-show rule) last.
  defp group_order("Claude Code"), do: {0, ""}
  defp group_order("Codex"), do: {1, ""}
  defp group_order("Current"), do: {3, ""}
  defp group_order(group), do: {2, group}

  defp pi_group?([%{provider: "pi"} | _]), do: true
  defp pi_group?(_), do: false

  defp entry_to_json(entry) do
    %{
      provider: entry.provider,
      slug: entry.slug,
      label: entry.label,
      group: entry.group,
      premium: entry.premium?,
      legacy: entry.legacy?,
      default: entry.default?
    }
  end
end
