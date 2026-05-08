defmodule EyeInTheSkyWeb.Components.DmPage.Composer.PromptQueue do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Helpers.ModelHelpers

  attr :prompts, :list, required: true

  def prompt_queue(assigns) do
    ~H"""
    <details class="group mb-2" open>
      <summary class="flex items-center gap-2 px-3 py-1.5 rounded-xl border border-base-content/8 bg-base-content/[0.02] cursor-pointer list-none hover:bg-base-content/[0.04] transition-colors select-none">
        <.icon name="hero-clock" class="size-3.5 text-warning/70" />
        <span class="text-mini font-medium text-base-content/40 flex-1 uppercase tracking-wide">
          {length(@prompts)} queued
        </span>
        <.icon name="hero-chevron-down" class="size-3 text-base-content/20" />
      </summary>
      <div class="mt-1 rounded-xl border border-base-content/8 bg-base-content/[0.02] divide-y divide-base-content/5 overflow-hidden">
        <%= for prompt <- @prompts do %>
          <div class="flex items-center gap-2 px-3 py-2">
            <span class="flex-shrink-0 text-xs font-mono font-medium uppercase tracking-wide px-1.5 py-0.5 rounded bg-base-content/[0.06] text-base-content/40">
              {model_display_name(prompt.context[:model] || "opus")}
            </span>
            <span class="text-xs text-base-content/50 truncate flex-1 min-w-0">
              {String.slice(prompt.message || "", 0, 80)}{if String.length(prompt.message || "") > 80,
                do: "…"}
            </span>
            <button
              type="button"
              phx-click="remove_queued_prompt"
              phx-value-id={prompt.id}
              class="flex-shrink-0 text-base-content/20 hover:text-error transition-colors"
              title="Remove from queue"
            >
              <.icon name="hero-x-mark-mini" class="size-4" />
            </button>
          </div>
        <% end %>
      </div>
    </details>
    """
  end

  defp model_display_name(slug), do: ModelHelpers.model_display_name(slug)
end
