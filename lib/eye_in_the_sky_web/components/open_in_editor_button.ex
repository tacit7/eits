defmodule EyeInTheSkyWeb.Components.OpenInEditorButton do
  @moduledoc """
  Split-button that opens content in an external editor.

  Supports two mutually exclusive modes — exactly one must be set:

  - **File mode** (`path`): opens a file path directly via `Editors.open/2`.
  - **Record mode** (`record_id`): opens DB-backed content via `EditorSync.open/3`
    and syncs saves back to the DB automatically.

  Usage (file mode):
      <.open_in_editor_button
        path={@selected_skill.abs_path}
        installed_editors={@installed_editors}
        preferred_editor={@preferred_editor}
      />

  Usage (record mode):
      <.open_in_editor_button
        record_id={@selected_note.id}
        installed_editors={@installed_editors}
        preferred_editor={@preferred_editor}
      />

  The emitted event is `open_in_editor` in both cases, with:
  - File mode: `phx-value-path`
  - Record mode: `phx-value-id`

  The parent LiveView handler checks which value is present and dispatches
  to `Editors.open/2` or `EditorSync.open/3` accordingly.

  Renders nothing when no editors are installed or the active value is
  nil/empty.
  """

  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  attr :path, :string, default: nil
  attr :record_id, :integer, default: nil
  attr :installed_editors, :list, default: []
  attr :preferred_editor, :string, default: "code"

  def open_in_editor_button(assigns) do
    # Exactly one of path or record_id must be set.
    path_set? = is_binary(assigns.path) && assigns.path != ""
    id_set? = not is_nil(assigns.record_id)

    if path_set? == id_set? do
      raise "OpenInEditorButton: exactly one of path or record_id is required " <>
              "(path=#{inspect(assigns.path)}, record_id=#{inspect(assigns.record_id)})"
    end

    preferred =
      Enum.find(assigns.installed_editors, &(&1.id == assigns.preferred_editor)) ||
        List.first(assigns.installed_editors)

    others =
      Enum.reject(assigns.installed_editors, &(&1.id == (preferred || %{})[:id]))

    assigns =
      assigns
      |> assign(:preferred, preferred)
      |> assign(:others, others)
      |> assign(:active, path_set? || id_set?)

    ~H"""
    <%= if @preferred && @active do %>
      <div class="join">
        <button
          class="btn btn-ghost btn-xs join-item gap-1.5 min-h-[30px] h-[30px]"
          phx-click="open_in_editor"
          phx-value-editor={@preferred.id}
          phx-value-path={@path}
          phx-value-id={@record_id}
          title={"Open in #{@preferred.label}"}
        >
          <.icon name="hero-arrow-top-right-on-square" class="size-3.5" />
          <span class="text-mini font-normal">{@preferred.label}</span>
        </button>
        <%= if @others != [] do %>
          <div class="dropdown dropdown-end join-item">
            <button
              tabindex="0"
              class="btn btn-ghost btn-xs join-item px-1 min-h-[30px] h-[30px] border-l border-base-content/10"
              title="Open in..."
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
                    class="text-mini"
                    phx-click="open_in_editor"
                    phx-value-editor={ed.id}
                    phx-value-path={@path}
                    phx-value-id={@record_id}
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
