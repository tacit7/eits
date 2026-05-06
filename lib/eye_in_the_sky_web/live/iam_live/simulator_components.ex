defmodule EyeInTheSkyWeb.IAMLive.SimulatorComponents do
  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents, only: [icon: 1]

  attr :permission, :atom, required: true
  attr :fallback?, :boolean, required: true

  def permission_badge(assigns) do
    {color, icon} =
      case assigns.permission do
        :allow -> {"badge-success", "hero-check-circle"}
        :deny -> {"badge-error", "hero-x-circle"}
        :instruct -> {"badge-warning", "hero-exclamation-triangle"}
      end

    assigns = assign(assigns, :color, color) |> assign(:icon_name, icon)

    ~H"""
    <div class="flex items-center gap-3">
      <span class={"badge #{@color} badge-lg gap-2"}>
        <.icon name={@icon_name} class="size-4" />
        {@permission}
      </span>
      <%= if @fallback? do %>
        <span class="badge badge-ghost">fallback (no policy matched)</span>
      <% end %>
    </div>
    """
  end

  attr :decision, :any, required: true

  def winner_card(assigns) do
    ~H"""
    <%= if @decision.winning_policy do %>
      <div class="card bg-base-100 border border-base-300">
        <div class="card-body p-4">
          <div class="flex items-start justify-between gap-3">
            <div>
              <div class="text-xs text-base-content/60">Winning policy</div>
              <div class="font-semibold">{@decision.winning_policy.name}</div>
              <div class="text-xs text-base-content/70 mt-1">
                id={@decision.winning_policy.id} · effect=<code><%= @decision.winning_policy.effect %></code> · priority={@decision.winning_policy.priority}
              </div>
            </div>
            <span class={"badge " <> effect_badge(@decision.winning_policy.effect)}>
              {@decision.winning_policy.effect}
            </span>
          </div>
          <%= if @decision.reason do %>
            <div class="text-sm mt-2 p-2 bg-base-200 rounded">
              {@decision.reason}
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  attr :instructions, :list, required: true

  def instructions_list(assigns) do
    ~H"""
    <%= if @instructions != [] do %>
      <div class="card bg-base-100 border border-base-300">
        <div class="card-body p-4">
          <div class="text-xs text-base-content/60 flex items-center gap-2 mb-2">
            <.icon name="hero-megaphone" class="size-4" /> Instructions ({length(@instructions)})
          </div>
          <ul class="space-y-2">
            <%= for %{policy: p, message: msg} <- @instructions do %>
              <li class="text-sm border-l-4 border-warning pl-3">
                <div class="font-medium">{p.name}</div>
                <div class="text-base-content/70">{msg}</div>
              </li>
            <% end %>
          </ul>
        </div>
      </div>
    <% end %>
    """
  end

  attr :traces, :list, required: true
  attr :winner_id, :any, required: true

  def trace_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-sm">
        <thead>
          <tr>
            <th></th>
            <th>ID</th>
            <th>Name</th>
            <th>Effect</th>
            <th>Priority</th>
            <th>Matched?</th>
            <th>Reason</th>
          </tr>
        </thead>
        <tbody>
          <%= for t <- @traces do %>
            <tr class={row_class(t, @winner_id)}>
              <td>
                <%= if t.policy.id == @winner_id do %>
                  <.icon name="hero-trophy" class="size-4 text-warning" />
                <% end %>
              </td>
              <td class="font-mono text-xs">{t.policy.id}</td>
              <td>{t.policy.name}</td>
              <td>
                <span class={"badge badge-sm " <> effect_badge(t.policy.effect)}>
                  {t.policy.effect}
                </span>
              </td>
              <td>{t.policy.priority}</td>
              <td>
                <%= if t.matched? do %>
                  <span class="badge badge-sm badge-success">match</span>
                <% else %>
                  <span class="badge badge-sm badge-ghost">miss</span>
                <% end %>
              </td>
              <td class="font-mono text-xs text-base-content/70">{format_reason(t.reason)}</td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp row_class(%{policy: %{id: id}}, winner_id) when id == winner_id and not is_nil(winner_id),
    do: "bg-success/10"

  defp row_class(%{matched?: true}, _), do: "bg-base-100"
  defp row_class(_, _), do: ""

  defp effect_badge("allow"), do: "badge-success"
  defp effect_badge("deny"), do: "badge-error"
  defp effect_badge("instruct"), do: "badge-warning"
  defp effect_badge(_), do: "badge-ghost"

  defp format_reason(:ok), do: "ok"
  defp format_reason({:miss, axis}), do: "miss: #{axis}"
  defp format_reason(other), do: inspect(other)
end
