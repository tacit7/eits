defmodule EyeInTheSkyWebWeb.Components.FileBrowser do
  @moduledoc """
  File browser components (tree view items).
  """

  use EyeInTheSkyWebWeb, :html

  attr :item, :map, required: true
  attr :project_id, :integer, required: true

  def tree_item(assigns) do
    case assigns.item.type do
      :directory -> directory_item(assigns)
      :file -> file_item(assigns)
    end
  end

  defp directory_item(assigns) do
    ~H"""
    <li>
      <details>
        <summary>
          <.icon name="hero-folder" class="w-4 h-4" />
          {@item.name}
        </summary>
        <ul>
          <.tree_item :for={child <- @item.children} item={child} project_id={@project_id} />
        </ul>
      </details>
    </li>
    """
  end

  defp file_item(assigns) do
    ~H"""
    <li>
      <.link patch={~p"/projects/#{@project_id}/files?path=#{@item.path}"}>
        <.icon name="hero-document-text" class="w-4 h-4" />
        {@item.name}
        <%= if @item.size do %>
          <span class="badge badge-ghost badge-xs ml-auto">{@item.size}</span>
        <% end %>
      </.link>
    </li>
    """
  end
end
