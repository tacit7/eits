defmodule EyeInTheSkyWeb.Components.DmPage.DiffSideBySide do
  @moduledoc """
  Server-rendered side-by-side diff component.

  Takes a parsed FileDiff (from EyeInTheSky.Diff.Parser) and renders
  a two-column grid with line numbers, +/- prefixes, and color coding.
  No JS required — pure HEEx + Tailwind.
  """

  use EyeInTheSkyWeb, :html

  alias EyeInTheSky.Diff.Parser

  attr :diff, :map, required: true

  def side_by_side(assigns) do
    ~H"""
    <%= if @diff.is_binary do %>
      <div class="px-4 py-3 text-xs text-base-content/40 italic">Binary file</div>
    <% else %>
      <div class="overflow-x-auto font-mono text-[11px] leading-5">
        <%= if @diff.hunks == [] do %>
          <div class="px-4 py-3 text-xs text-base-content/40 italic">No changes</div>
        <% else %>
          <%= for hunk <- @diff.hunks do %>
            <%!-- Hunk header --%>
            <div class="px-3 py-0.5 bg-info/10 text-info/70 text-[10px] border-y border-info/10 select-none">
              {hunk.header}
            </div>
            <%!-- Side-by-side rows --%>
            <%= for {left, right} <- Parser.pair_lines(hunk.lines) do %>
              <div class="grid grid-cols-2 divide-x divide-base-content/5 min-w-0">
                <.sbs_cell side={left} />
                <.sbs_cell side={right} />
              </div>
            <% end %>
          <% end %>
        <% end %>
      </div>
    <% end %>
    """
  end

  # A single cell (left or right). nil = empty (no corresponding line).
  defp sbs_cell(%{side: nil} = assigns) do
    ~H"""
    <div class="flex min-w-0 bg-base-300/20">
      <span class="w-10 flex-shrink-0 text-right pr-2 text-base-content/20 select-none border-r border-base-content/5">
      </span>
      <span class="w-3 flex-shrink-0 text-center text-base-content/20 select-none"></span>
      <span class="flex-1 px-2 whitespace-pre overflow-hidden"></span>
    </div>
    """
  end

  defp sbs_cell(%{side: line} = assigns) when line.type == :added do
    ~H"""
    <div class="flex min-w-0 bg-success/10">
      <span class="w-10 flex-shrink-0 text-right pr-2 text-base-content/30 select-none border-r border-base-content/5">
        {@side.new_line_number}
      </span>
      <span class="w-3 flex-shrink-0 text-center text-success/70 select-none">+</span>
      <span class="flex-1 px-2 whitespace-pre overflow-hidden text-base-content/90">
        {@side.content}
      </span>
    </div>
    """
  end

  defp sbs_cell(%{side: line} = assigns) when line.type == :removed do
    ~H"""
    <div class="flex min-w-0 bg-error/10">
      <span class="w-10 flex-shrink-0 text-right pr-2 text-base-content/30 select-none border-r border-base-content/5">
        {@side.old_line_number}
      </span>
      <span class="w-3 flex-shrink-0 text-center text-error/70 select-none">-</span>
      <span class="flex-1 px-2 whitespace-pre overflow-hidden text-base-content/90">
        {@side.content}
      </span>
    </div>
    """
  end

  defp sbs_cell(%{side: line} = assigns) when line.type == :context do
    ~H"""
    <div class="flex min-w-0">
      <span class="w-10 flex-shrink-0 text-right pr-2 text-base-content/20 select-none border-r border-base-content/5">
        {@side.old_line_number}
      </span>
      <span class="w-3 flex-shrink-0 text-center text-base-content/20 select-none"> </span>
      <span class="flex-1 px-2 whitespace-pre overflow-hidden text-base-content/60">
        {@side.content}
      </span>
    </div>
    """
  end
end
