defmodule EyeInTheSkyWeb.OverviewLive.Settings.AuthTab do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.OverviewLive.Settings.TabHelpers

  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <section>
        <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
          API Keys
        </h2>
        <div class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body p-0 divide-y divide-base-300">
            <%!-- Anthropic API Key --%>
            <div class="flex items-center justify-between px-5 py-4">
              <div>
                <p class="text-sm font-medium text-base-content">Anthropic API Key</p>
                <p class="text-xs text-base-content/50 mt-0.5">
                  Set via ANTHROPIC_API_KEY in your .env
                </p>
              </div>
              <%= case mask_env_var("ANTHROPIC_API_KEY") do %>
                <% {:set, masked} -> %>
                  <span class="badge badge-success badge-sm font-mono">{masked}</span>
                <% {:not_set, _} -> %>
                  <span class="text-xs text-warning">Not configured</span>
              <% end %>
            </div>
            <%!-- EITS REST API Key --%>
            <div class="px-5 py-4">
              <div class="flex items-center justify-between mb-2">
                <div>
                  <p class="text-sm font-medium text-base-content">EITS REST API Key</p>
                  <p class="text-xs text-base-content/50 mt-0.5">Set via EITS_API_KEY in your .env</p>
                </div>
                <%= case mask_env_var("EITS_API_KEY") do %>
                  <% {:set, masked} -> %>
                    <span class="badge badge-success badge-sm font-mono">{masked}</span>
                  <% {:not_set, _} -> %>
                    <span class="text-xs text-warning">Not configured</span>
                <% end %>
              </div>
              <%= if @generated_api_key do %>
                <div class="alert alert-warning mt-2 p-3 text-xs">
                  <p class="font-semibold mb-1">Copy this key now — it will not be shown again.</p>
                  <p class="mb-2">
                    Add to .env: <code class="font-mono">EITS_API_KEY=&lt;value&gt;</code>
                    then restart.
                  </p>
                  <input
                    type="text"
                    readonly
                    value={@generated_api_key}
                    class="input input-bordered input-xs font-mono w-full text-base"
                  />
                </div>
              <% else %>
                <button phx-click="regenerate_api_key" class="btn btn-sm btn-outline mt-2">
                  Regenerate
                </button>
              <% end %>
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end
end
