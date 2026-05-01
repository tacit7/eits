defmodule EyeInTheSkyWeb.Components.Rail.Flyout.FilesSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Components.Rail.Flyout.Helpers

  attr :file_nodes, :list, default: []
  attr :file_expanded, :any, default: nil
  attr :file_children, :map, default: %{}
  attr :file_error, :string, default: nil
  attr :sidebar_project, :any, default: nil
  attr :myself, :any, required: true

  def files_content(assigns) do
    assigns =
      assign(
        assigns,
        :flat_rows,
        flatten_file_tree(
          assigns.file_nodes,
          assigns.file_children,
          assigns.file_expanded || MapSet.new(),
          0
        )
      )

    ~H"""
    <%= if is_nil(@sidebar_project) || is_nil(@sidebar_project.path) do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No project path configured</div>
    <% else %>
      <%!-- Error state --%>
      <%= if @file_error do %>
        <div class="px-3 py-2 text-xs text-error/70">{@file_error}</div>
      <% end %>

      <%!-- Tree rows --%>
      <%= for {node, depth} <- @flat_rows do %>
        <% indent = depth * 12 %>
        <%= case node.type do %>
          <% :directory -> %>
            <% expanded = MapSet.member?(@file_expanded, node.path) %>
            <button
              phx-click={if expanded, do: "file_collapse", else: "file_expand"}
              phx-value-path={node.path}
              phx-target={@myself}
              class="w-full flex items-center gap-1.5 pr-3 py-[3px] text-left text-xs text-base-content/70 hover:text-base-content/90 hover:bg-base-content/5 transition-colors"
              style={"padding-left: #{indent + 8}px"}
            >
              <.icon
                name={if expanded, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
                class="size-3 text-base-content/30 flex-shrink-0"
              />
              <.icon
                name={if expanded, do: "hero-folder-open-mini", else: "hero-folder-mini"}
                class="size-3.5 text-base-content/40 flex-shrink-0"
              />
              <span class="truncate">{node.name}</span>
            </button>
          <% :file -> %>
            <button
              phx-click="file_open"
              phx-value-path={node.path}
              phx-target={@myself}
              class="w-full flex items-center gap-1.5 pr-3 py-[3px] text-left text-xs text-base-content/55 hover:text-base-content/85 hover:bg-base-content/5 transition-colors"
              style={"padding-left: #{indent + 20}px"}
            >
              <%= if node.sensitive? do %>
                <.icon name="hero-lock-closed-mini" class="size-3.5 text-warning/50 flex-shrink-0" />
              <% else %>
                <.icon name="hero-document-mini" class="size-3.5 text-base-content/20 flex-shrink-0" />
              <% end %>
              <span class="truncate">{node.name}</span>
            </button>
          <% :warning -> %>
            <div
              class="px-3 py-1 text-micro text-base-content/25 italic"
              style={"padding-left: #{indent + 8}px"}
            >
              {node.name}
            </div>
          <% _ -> %>
        <% end %>
      <% end %>

      <%= if @flat_rows == [] && is_nil(@file_error) do %>
        <div class="px-3 py-4 text-xs text-base-content/35 text-center">Empty</div>
      <% end %>

      <%!-- Footer --%>
      <div class="border-t border-base-content/8 mt-2">
        <Helpers.simple_link
          href={"/projects/#{@sidebar_project.id}/files"}
          label="Open File Browser"
          icon="hero-arrow-top-right-on-square"
        />
      </div>
    <% end %>
    """
  end

  def flatten_file_tree(nodes, children_cache, expanded, depth) do
    Enum.flat_map(nodes, fn node ->
      if node.type == :directory && MapSet.member?(expanded, node.path) do
        kids = Map.get(children_cache, node.path, [])
        [{node, depth} | flatten_file_tree(kids, children_cache, expanded, depth + 1)]
      else
        [{node, depth}]
      end
    end)
  end
end
