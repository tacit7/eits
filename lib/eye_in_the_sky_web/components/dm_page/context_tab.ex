defmodule EyeInTheSkyWeb.Components.DmPage.ContextTab do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  attr :session_context, :map, default: nil

  def context_tab(assigns) do
    ~H"""
    <div class="space-y-3 p-1" id="dm-context-tab">
      <%= if is_nil(@session_context) do %>
        <.empty_state
          id="dm-context-empty"
          icon="hero-document-magnifying-glass"
          title="No context yet"
          subtitle="Session context will appear here once set"
        />
      <% else %>
        <div class="bg-base-200 rounded-xl shadow-sm" id="dm-context-content">
          <%!-- Meta row --%>
          <div class="flex items-center justify-between px-4 pt-3 pb-2 border-b border-base-content/5">
            <span class="text-[11px] font-semibold uppercase tracking-wider text-base-content/35">
              Session Context
            </span>
            <time
              id="context-updated-at"
              class="text-[11px] font-mono text-base-content/30 tabular-nums"
              data-utc={to_utc_string(@session_context.updated_at)}
              data-fmt="short"
              phx-hook="LocalTime"
            >
            </time>
          </div>
          <%!-- Context body --%>
          <div class="px-4 py-3 overflow-x-auto">
            <pre class="whitespace-pre-wrap text-xs font-mono text-base-content/65 leading-relaxed">{@session_context.context}</pre>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp to_utc_string(nil), do: ""
  defp to_utc_string(ts) when is_binary(ts), do: ts
  defp to_utc_string(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp to_utc_string(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt) <> "Z"
  defp to_utc_string(_), do: ""
end
