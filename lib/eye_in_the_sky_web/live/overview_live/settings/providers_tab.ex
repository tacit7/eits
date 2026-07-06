defmodule EyeInTheSkyWeb.OverviewLive.Settings.ProvidersTab do
  @moduledoc false
  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <section>
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider">
            Providers
          </h2>
          <button
            type="button"
            phx-click="pi_refresh_models"
            class="btn btn-sm btn-outline"
          >
            Refresh models
          </button>
        </div>

        <div class="alert alert-info alert-soft mb-4 text-xs">
          <p>
            EITS Pi uses ~/.pi/agent/auth.json only. Environment credentials
            (including ANTHROPIC_API_KEY) are intentionally not passed into the harness.
          </p>
        </div>

        <div class="text-xs text-base-content/60 mb-3">
          {model_status_line(@pi_model_status)}
        </div>

        <div class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body p-0 divide-y divide-base-300">
            {render_providers(assigns)}
          </div>
        </div>
      </section>
    </div>
    """
  end

  defp render_providers(%{pi_providers: :loading} = assigns) do
    ~H"""
    <div class="px-5 py-4 text-sm text-base-content/50">Loading providers…</div>
    """
  end

  defp render_providers(%{pi_providers: {:error, reason}} = assigns) do
    assigns = assign(assigns, :reason, reason)

    ~H"""
    <div class="px-5 py-4 text-sm text-error">
      Could not load providers: {inspect(@reason)}
    </div>
    """
  end

  defp render_providers(%{pi_providers: {:ok, payload}} = assigns) do
    assigns = assign(assigns, :providers, providers_list(payload))

    ~H"""
    <div :for={p <- @providers} class="px-5 py-4">
      <div class="flex items-center justify-between mb-2">
        <div>
          <p class="text-sm font-medium text-base-content">{p["label"] || p["id"]}</p>
          <p class="text-xs text-base-content/50 mt-0.5 font-mono">{p["id"]}</p>
        </div>
        {configured_badge(configured?(p))}
      </div>
      {render_provider_actions(assign(assigns, :p, p))}
    </div>
    """
  end

  defp render_provider_actions(%{p: %{"kind" => "oauth"} = _p} = assigns) do
    ~H"""
    <div class="mt-2">
      <button type="button" class="btn btn-sm btn-outline" disabled>Sign in (Phase 3)</button>
    </div>
    """
  end

  defp render_provider_actions(%{p: p} = assigns) do
    assigns =
      assigns
      |> assign(:provider_id, p["id"])
      |> assign(:configured?, configured?(p))

    ~H"""
    <form
      phx-submit="pi_set_key"
      data-provider-id={@provider_id}
      class="flex flex-wrap items-center gap-2 mt-2"
    >
      <input type="hidden" name="provider_id" value={@provider_id} />
      <input
        type="password"
        name="key"
        autocomplete="off"
        placeholder="API key"
        class="input input-bordered input-sm flex-1 font-mono min-w-[12rem]"
      />
      <button type="submit" class="btn btn-sm btn-primary">Save</button>
      <button
        :if={@configured?}
        type="button"
        class="btn btn-sm btn-outline"
        phx-click="pi_clear_key"
        phx-value-provider_id={@provider_id}
      >
        Clear
      </button>
    </form>
    """
  end

  defp providers_list(%{"providers" => list}) when is_list(list), do: list
  defp providers_list(list) when is_list(list), do: list
  defp providers_list(_), do: []

  defp configured?(%{"authSource" => src}) when is_binary(src) and src != "", do: true
  defp configured?(%{"configured" => true}), do: true
  defp configured?(_), do: false

  defp configured_badge(true) do
    assigns = %{}
    ~H|<span class="badge badge-success badge-sm">configured</span>|
  end

  defp configured_badge(false) do
    assigns = %{}
    ~H|<span class="badge badge-ghost badge-sm">not set</span>|
  end

  defp model_status_line(:loading), do: "Model discovery: loading…"

  defp model_status_line({count, :fresh}) when is_integer(count),
    do: "Model discovery: #{count} model(s) cached (fresh)"

  defp model_status_line({count, :stale}) when is_integer(count),
    do: "Model discovery: #{count} model(s) cached (stale — refresh)"

  defp model_status_line(:empty), do: "Model discovery: no cached models yet"

  defp model_status_line({:error, reason}),
    do: "Model discovery failed: #{inspect(reason)}"

  defp model_status_line(_), do: ""
end
