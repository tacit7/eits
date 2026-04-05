defmodule EyeInTheSkyWeb.OverviewLive.Settings.PricingTab do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  def render(assigns) do
    ~H"""
    <section>
      <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
        Token Pricing
      </h2>
      <div class="card bg-base-100 border border-base-300 shadow-sm">
        <div class="card-body p-5">
          <div class="flex items-center justify-between mb-4">
            <p class="text-xs text-base-content/50">
              Cost per 1M tokens (USD). Used for usage cost estimates.
            </p>
            <button phx-click="reset_pricing" class="btn btn-ghost btn-xs">
              <.icon name="hero-arrow-uturn-left" class="w-3.5 h-3.5" /> Reset All
            </button>
          </div>
          <form phx-change="save_pricing" phx-debounce="500">
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr class="text-base-content/60">
                    <th>Model</th>
                    <th class="text-right">Input</th>
                    <th class="text-right">Output</th>
                    <th class="text-right">Cache Read</th>
                    <th class="text-right">Cache Create</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={model <- ["opus", "sonnet", "haiku"]} class="hover">
                    <td class="font-medium capitalize">{model}</td>
                    <td
                      :for={type <- ["input", "output", "cache_read", "cache_creation"]}
                      class="text-right"
                    >
                      <input
                        type="number"
                        name={"pricing_#{model}_#{type}"}
                        value={@settings["pricing_#{model}_#{type}"]}
                        step="0.01"
                        min="0"
                        class="input input-bordered input-xs w-20 text-right"
                      />
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </form>
        </div>
      </div>
    </section>
    """
  end
end
