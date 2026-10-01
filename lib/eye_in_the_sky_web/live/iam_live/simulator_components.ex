defmodule EyeInTheSkyWeb.IAMLive.SimulatorComponents do
  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents, only: [icon: 1]

  attr :permission, :atom, required: true
  attr :fallback?, :boolean, required: true

  def permission_badge(assigns) do
    {tone, icon} =
      case assigns.permission do
        :allow -> {"eits-chip--success", "hero-check-circle"}
        :deny -> {"eits-chip--error", "hero-x-circle"}
        :instruct -> {"eits-chip--warning", "hero-exclamation-triangle"}
      end

    assigns = assign(assigns, :tone, tone) |> assign(:icon_name, icon)

    ~H"""
    <div class="flex items-center gap-3">
      <span class={["eits-chip px-2 py-1 text-message", @tone]}>
        <.icon name={@icon_name} class="size-4" />
        {@permission}
      </span>
      <%= if @fallback? do %>
        <span class="eits-chip eits-chip--neutral">
          fallback (no policy matched)
        </span>
      <% end %>
    </div>
    """
  end

  attr :decision, :any, required: true

  def winner_card(assigns) do
    ~H"""
    <%= if @decision.winning_policy do %>
      <div class="eits-panel bg-base-100 border border-base-300">
        <div class="eits-panel__body p-4">
          <div class="flex items-start justify-between gap-3">
            <div>
              <div class="text-mini text-base-content/60">Winning policy</div>
              <div class="font-semibold">{@decision.winning_policy.name}</div>
              <div class="text-mini text-base-content/70 mt-1 flex flex-wrap items-center gap-x-2 gap-y-1">
                <span>id={@decision.winning_policy.id}</span>
                <span>
                  effect=<code><%= @decision.winning_policy.effect %></code>
                </span>
                <span>priority={@decision.winning_policy.priority}</span>
              </div>
            </div>
            <span class={["eits-chip", effect_badge(@decision.winning_policy.effect)]}>
              {@decision.winning_policy.effect}
            </span>
          </div>
          <%= if @decision.reason do %>
            <div class="text-message mt-2 p-2 bg-base-200 rounded-box">
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
      <div class="eits-panel bg-base-100 border border-base-300">
        <div class="eits-panel__body p-4">
          <div class="text-mini text-base-content/60 flex items-center gap-2 mb-2">
            <.icon name="hero-megaphone" class="size-4" /> Instructions ({length(@instructions)})
          </div>
          <ul class="space-y-2">
            <%= for %{policy: p, message: msg} <- @instructions do %>
              <li class="text-message rounded-box border border-warning/20 bg-warning/10 px-3 py-2">
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
            <th>Source</th>
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
              <td class="font-mono text-mini">{t.policy.id}</td>
              <td>{t.policy.name}</td>
              <td>
                <span class={["eits-chip", effect_badge(t.policy.effect)]}>
                  {t.policy.effect}
                </span>
              </td>
              <td>{t.policy.priority}</td>
              <td class="text-mini text-base-content/60">
                {EyeInTheSky.IAM.EvaluationSource.label(Map.get(t, :source, :global))}
              </td>
              <td>
                <%= if t.matched? do %>
                  <span class="eits-chip eits-chip--success">match</span>
                <% else %>
                  <span class="eits-chip eits-chip--neutral">miss</span>
                <% end %>
              </td>
              <td class="font-mono text-mini text-base-content/70">{format_reason(t.reason)}</td>
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

  defp effect_badge("allow"), do: "eits-chip--success"
  defp effect_badge("deny"), do: "eits-chip--error"
  defp effect_badge("instruct"), do: "eits-chip--warning"
  defp effect_badge(_), do: "eits-chip--neutral"

  defp format_reason(:ok), do: "ok"
  defp format_reason({:miss, axis}), do: "miss: #{axis}"
  defp format_reason(other), do: inspect(other)
end
