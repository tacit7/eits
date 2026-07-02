defmodule EyeInTheSkyWeb.Components.OpenInEditorButton do
  @moduledoc """
  Split-button that opens a file path in an external editor.

  Primary half — one click, opens in the preferred editor.
  Chevron half — dropdown listing every other detected editor.

  Usage:
      <.open_in_editor_button
        path={@selected_skill.abs_path}
        installed_editors={@installed_editors}
        preferred_editor={@preferred_editor}
      />

  Renders nothing when `path` is nil/empty or no editors are installed.
  """

  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  attr :path, :string, required: true
  attr :installed_editors, :list, default: []
  attr :preferred_editor, :string, default: "code"

  def open_in_editor_button(assigns) do
    preferred =
      Enum.find(assigns.installed_editors, &(&1.id == assigns.preferred_editor)) ||
        List.first(assigns.installed_editors)

    others =
      Enum.reject(assigns.installed_editors, &(&1.id == (preferred || %{})[:id]))

    assigns =
      assigns
      |> assign(:preferred, preferred)
      |> assign(:others, others)

    ~H"""
    <%= if @preferred && is_binary(@path) && @path != "" do %>
      <div class="join">
        <button
          class="btn btn-ghost btn-xs join-item gap-1.5 min-h-[30px] h-[30px]"
          phx-click="open_in_editor"
          phx-value-editor={@preferred.id}
          phx-value-path={@path}
          title={"Open in #{@preferred.label}"}
        >
          <.icon name="hero-arrow-top-right-on-square" class="size-3.5" />
          <span class="text-xs font-normal">{@preferred.label}</span>
        </button>
        <%= if @others != [] do %>
          <div class="dropdown dropdown-end join-item">
            <button
              tabindex="0"
              class="btn btn-ghost btn-xs join-item px-1 min-h-[30px] h-[30px] border-l border-base-content/10"
              title="Open in…"
            >
              <.icon name="hero-chevron-down" class="size-3" />
            </button>
            <ul
              tabindex="0"
              class="dropdown-content menu bg-base-200 border border-base-content/10 rounded-box z-50 w-40 shadow-lg p-1 mt-1"
            >
              <%= for ed <- @others do %>
                <li>
                  <button
                    class="text-xs"
                    phx-click="open_in_editor"
                    phx-value-editor={ed.id}
                    phx-value-path={@path}
                  >
                    {ed.label}
                  </button>
                </li>
              <% end %>
            </ul>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end
end
