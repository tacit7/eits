defmodule EyeInTheSkyWeb.Components.DmPage.ContextTab do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  import EyeInTheSkyWeb.Components.DmHelpers, only: [to_utc_string: 1]

  attr :session_context, :map, default: nil

  def context_tab(assigns) do
    assigns =
      assign(assigns, :sections, parse_sections(assigns[:session_context]))

    ~H"""
    <div class="space-y-1" id="dm-context-tab">
      <%= if @sections == [] do %>
        <.empty_state
          id="dm-context-empty"
          icon="hero-document-magnifying-glass"
          title="No context yet"
          subtitle="Session context will appear here once set"
        />
      <% else %>
        <div class="space-y-1 bg-base-200 rounded-xl shadow-sm p-4" id="dm-context-list">
          <%= for {title, body, idx} <- @sections do %>
            <div
              class="collapse collapse-arrow rounded-lg border border-base-content/5 bg-base-200 hover:border-base-content/10 transition-colors"
              id={"dm-context-section-#{idx}"}
            >
              <input type="checkbox" />
              <div class="collapse-title py-3 px-4">
                <div class="flex items-center gap-3">
                  <.icon name="hero-document-text" class="w-4 h-4 flex-shrink-0 text-base-content/30" />
                  <div class="flex-1 min-w-0">
                    <h3 class="text-[13px] font-semibold text-base-content/85 truncate">
                      {title}
                    </h3>
                    <%= if idx == 0 and @session_context do %>
                      <div class="flex items-center gap-1.5 mt-0.5 text-[11px] text-base-content/30">
                        <time
                          id="context-updated-at"
                          class="tabular-nums"
                          data-utc={to_utc_string(@session_context.updated_at)}
                          data-fmt="short"
                          phx-hook="LocalTime"
                        >
                        </time>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
              <div class="collapse-content px-4 pb-4">
                <div class="pl-7">
                  <div
                    id={"context-body-#{idx}"}
                    class="dm-markdown text-sm text-base-content/70 leading-relaxed"
                    phx-hook="MarkdownMessage"
                    data-raw-body={body}
                  >
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp parse_sections(nil), do: []

  defp parse_sections(%{context: context}) when is_binary(context) do
    context
    |> String.split(~r/\n---\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index()
    |> Enum.map(fn {section, idx} ->
      title = extract_title(section)
      {title, section, idx}
    end)
  end

  defp parse_sections(_), do: []

  defp extract_title(section) do
    section
    |> String.split("\n")
    |> Enum.find(&String.starts_with?(&1, "#"))
    |> case do
      nil -> "Section"
      line -> line |> String.replace(~r/^#+\s*/, "") |> String.trim()
    end
  end

end
