defmodule EyeInTheSkyWeb.IAMLive.Policies do
  @moduledoc """
  IAM policy index.

  Lists every policy row (system + user) with filters for agent_type, action,
  effect, and enabled. Supports quick-toggling the `enabled` flag, linking to
  the edit form, and deleting user policies. System policies (those carrying a
  `system_key`) cannot be deleted from the UI.
  """
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]
  import EyeInTheSkyWeb.IAMLive.IAMComponents

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.HooksChecker
  alias EyeInTheSky.IAM.Policy
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers

  @default_filters %{
    "agent_type" => "",
    "action" => "",
    "effect" => "",
    "enabled" => ""
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "IAM Policies")
      |> assign(:sidebar_tab, :iam)
      |> assign(:sidebar_project, nil)
      |> assign(:filters, @default_filters)
      |> assign(:iam_hooks_status, HooksChecker.status())

    socket =
      if connected?(socket) do
        assign_policies(socket)
      else
        assign(socket, :policies, [])
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    filters = Map.merge(@default_filters, Map.take(params, Map.keys(@default_filters)))

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign_policies()}
  end

  def handle_event("reset_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:filters, @default_filters)
     |> assign_policies()}
  end

  def handle_event("toggle", %{"id" => id, "enabled" => enabled}, socket) do
    case parse_int(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Invalid policy ID.")}

      id_int ->
        desired = enabled in ["true", "on", true]
        {_count, _} = IAM.bulk_toggle_enabled([id_int], desired)

        {:noreply,
         socket
         |> put_flash(:info, "Policy #{if desired, do: "enabled", else: "disabled"}.")
         |> assign_policies()}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with int_id when is_integer(int_id) <- parse_int(id),
         {:ok, %Policy{} = policy} <- IAM.get_policy(int_id),
         :ok <- refuse_system_delete(policy),
         {:ok, _} <- IAM.delete_policy(policy) do
      {:noreply,
       socket
       |> put_flash(:info, "Policy \"#{policy.name}\" deleted.")
       |> assign_policies()}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Policy not found.")}

      {:error, :system_policy} ->
        {:noreply, put_flash(socket, :error, "System policies cannot be deleted.")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, put_flash(socket, :error, "Delete failed: #{inspect(cs.errors)}")}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid policy ID.")}
    end
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp refuse_system_delete(%Policy{system_key: nil}), do: :ok
  defp refuse_system_delete(%Policy{}), do: {:error, :system_policy}

  defp assign_policies(socket) do
    assign(socket, :policies, IAM.list_policies(filters_to_query(socket.assigns.filters)))
  end

  defp filters_to_query(filters) do
    %{
      agent_type: blank_to_nil(filters["agent_type"]),
      action: blank_to_nil(filters["action"]),
      effect: blank_to_nil(filters["effect"]),
      enabled: parse_enabled(filters["enabled"])
    }
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(v) when is_binary(v), do: v

  defp parse_enabled("true"), do: true
  defp parse_enabled("false"), do: false
  defp parse_enabled(_), do: nil

  # ── rendering ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto space-y-6">
      <.iam_offline_banner hooks_status={@iam_hooks_status} />
      <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-3">
          <.icon name="hero-shield-check" class="size-6 text-primary" />
          <h1 class="text-2xl font-bold">IAM Policies</h1>
          <span class="badge badge-ghost"><%= length(@policies) %></span>
        </div>

        <div class="flex items-center gap-2">
          <.link navigate={~p"/iam/simulator"} class="btn btn-ghost btn-sm">
            <.icon name="hero-beaker" class="size-4" /> Simulator
          </.link>
          <.link navigate={~p"/iam/policies/new"} class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="size-4" /> New policy
          </.link>
        </div>
      </div>

      <section class="card bg-base-200">
        <div class="card-body p-4">
          <form id="iam-policies-filter" phx-change="filter" phx-submit="filter" class="grid grid-cols-1 md:grid-cols-5 gap-3 items-end">
            <label class="form-control">
              <span class="label-text text-xs">Agent type</span>
              <input type="text" name="filters[agent_type]" value={@filters["agent_type"]} placeholder="any" class="input input-bordered input-sm" />
            </label>
            <label class="form-control">
              <span class="label-text text-xs">Action</span>
              <input type="text" name="filters[action]" value={@filters["action"]} placeholder="any" class="input input-bordered input-sm" />
            </label>
            <label class="form-control">
              <span class="label-text text-xs">Effect</span>
              <select name="filters[effect]" class="select select-bordered select-sm">
                <option value="" selected={@filters["effect"] == ""}>any</option>
                <option value="allow" selected={@filters["effect"] == "allow"}>allow</option>
                <option value="deny" selected={@filters["effect"] == "deny"}>deny</option>
                <option value="instruct" selected={@filters["effect"] == "instruct"}>instruct</option>
              </select>
            </label>
            <label class="form-control">
              <span class="label-text text-xs">Enabled</span>
              <select name="filters[enabled]" class="select select-bordered select-sm">
                <option value="" selected={@filters["enabled"] == ""}>any</option>
                <option value="true" selected={@filters["enabled"] == "true"}>enabled</option>
                <option value="false" selected={@filters["enabled"] == "false"}>disabled</option>
              </select>
            </label>
            <button type="button" class="btn btn-ghost btn-sm" phx-click="reset_filters">Reset</button>
          </form>
        </div>
      </section>

      <section class="card bg-base-200">
        <div class="card-body p-0">
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Priority</th>
                  <th>Name</th>
                  <th>Effect</th>
                  <th>Agent</th>
                  <th>Action</th>
                  <th>Resource</th>
                  <th>Enabled</th>
                  <th>Kind</th>
                  <th class="text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= if @policies == [] do %>
                  <tr>
                    <td colspan="9" class="text-center py-8 text-base-content/60">
                      No policies match the current filters.
                    </td>
                  </tr>
                <% end %>
                <%= for p <- @policies do %>
                  <tr id={"policy-#{p.id}"}>
                    <td class="font-mono text-xs"><%= p.priority %></td>
                    <td>
                      <div class="font-medium"><%= p.name %></div>
                      <%= if p.system_key do %>
                        <div class="text-xs text-base-content/60 font-mono"><%= p.system_key %></div>
                      <% end %>
                    </td>
                    <td>
                      <span class={"badge badge-sm " <> effect_badge(p.effect)}><%= p.effect %></span>
                    </td>
                    <td class="font-mono text-xs"><%= p.agent_type %></td>
                    <td class="font-mono text-xs"><%= p.action %></td>
                    <td class="font-mono text-xs"><%= p.resource_glob || "—" %></td>
                    <td>
                      <button
                        type="button"
                        phx-click="toggle"
                        phx-value-id={p.id}
                        phx-value-enabled={to_string(not p.enabled)}
                        class={"btn btn-xs " <> (if p.enabled, do: "btn-success", else: "btn-ghost")}
                      >
                        <.icon name={if p.enabled, do: "hero-check-circle", else: "hero-x-circle"} class="size-4" />
                        <%= if p.enabled, do: "on", else: "off" %>
                      </button>
                    </td>
                    <td>
                      <%= if p.system_key do %>
                        <span class="badge badge-sm badge-info gap-1">
                          <.icon name="hero-lock-closed" class="size-3" /> system
                        </span>
                      <% else %>
                        <span class="badge badge-sm badge-ghost">user</span>
                      <% end %>
                    </td>
                    <td class="text-right whitespace-nowrap">
                      <.link navigate={~p"/iam/policies/#{p.id}/edit"} class="btn btn-ghost btn-xs">
                        <.icon name="hero-pencil-square" class="size-4" /> Edit
                      </.link>
                      <%= if p.system_key do %>
                        <button type="button" class="btn btn-ghost btn-xs btn-disabled" disabled title="System policies cannot be deleted">
                          <.icon name="hero-trash" class="size-4" />
                        </button>
                      <% else %>
                        <button
                          type="button"
                          class="btn btn-ghost btn-xs text-error"
                          phx-click="delete"
                          phx-value-id={p.id}
                          data-confirm={"Delete policy \"#{p.name}\"? This cannot be undone."}
                        >
                          <.icon name="hero-trash" class="size-4" />
                        </button>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </div>
    """
  end

  defp effect_badge("allow"), do: "badge-success"
  defp effect_badge("deny"), do: "badge-error"
  defp effect_badge("instruct"), do: "badge-warning"
  defp effect_badge(_), do: "badge-ghost"
end
