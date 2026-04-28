defmodule EyeInTheSkyWeb.OverviewLive.Keybindings do
  use EyeInTheSkyWeb, :live_view

  @commands [
    %{group: "navigation", label: "Go to", bindings: [
      %{keys: ["g", "s"], desc: "Sessions"},
      %{keys: ["g", "t"], desc: "Tasks"},
      %{keys: ["g", "n"], desc: "Notes"},
      %{keys: ["g", "a"], desc: "Agents"},
      %{keys: ["g", "k"], desc: "Kanban"},
      %{keys: ["g", "w"], desc: "Canvas"},
      %{keys: ["g", "f"], desc: "Files"},
      %{keys: ["g", "p"], desc: "Prompts"},
      %{keys: ["g", "c"], desc: "Chat"},
      %{keys: ["g", "j"], desc: "Jobs"},
      %{keys: ["g", "u"], desc: "Usage"},
      %{keys: ["g", "m"], desc: "Teams"},
      %{keys: ["g", "K"], desc: "Skills"},
      %{keys: ["g", "N"], desc: "Notifications"},
      %{keys: ["g", ","], desc: "Settings"},
      %{keys: ["g", "h"], desc: "Keybinding reference (this page)"},
    ]},
    %{group: "global", label: "Global", bindings: [
      %{keys: ["?"],   desc: "Keybinding help overlay"},
      %{keys: [":"],   desc: "Command palette"},
      %{keys: ["["],   desc: "Go back"},
      %{keys: ["]"],   desc: "Go forward"},
      %{keys: ["q"],   desc: "Close flyout"},
      %{keys: ["/"],   desc: "Focus search (when page has search)", scope: "feature:vim-search"},
    ]},
    %{group: "toggle", label: "Toggle rail sections", bindings: [
      %{keys: ["t", "s"], desc: "Sessions"},
      %{keys: ["t", "t"], desc: "Tasks"},
      %{keys: ["t", "n"], desc: "Notes"},
      %{keys: ["t", "f"], desc: "Files"},
      %{keys: ["t", "w"], desc: "Canvas"},
      %{keys: ["t", "c"], desc: "Chat"},
      %{keys: ["t", "k"], desc: "Skills"},
      %{keys: ["t", "m"], desc: "Teams"},
      %{keys: ["t", "j"], desc: "Jobs"},
      %{keys: ["t", "a"], desc: "Agents"},
      %{keys: ["t", "u"], desc: "Usage"},
      %{keys: ["t", "b"], desc: "Notifications (bell)"},
      %{keys: ["t", "P"], desc: "Prompts"},
      %{keys: ["t", "p"], desc: "Project picker"},
    ]},
    %{group: "create", label: "Create", bindings: [
      %{keys: ["n", "a"], desc: "New agent"},
      %{keys: ["n", "t"], desc: "New task"},
      %{keys: ["n", "n"], desc: "New note"},
      %{keys: ["n", "c"], desc: "New chat"},
    ]},
    %{group: "context", label: "List navigation", scope_note: "Pages with a navigable list", bindings: [
      %{keys: ["j"],     desc: "Next item"},
      %{keys: ["k"],     desc: "Previous item"},
      %{keys: ["Enter"], desc: "Open item"},
    ]},
    %{group: "context", label: "Sessions page", scope_note: "Sessions page only", bindings: [
      %{keys: ["A"],      desc: "Archive focused session"},
      %{keys: ["D"],      desc: "Delete focused session"},
      %{keys: ["y", "u"], desc: "Copy session UUID"},
      %{keys: ["y", "i"], desc: "Copy session integer ID"},
    ]},
    %{group: "context", label: "Flyout navigation", scope_note: "When flyout panel is open", bindings: [
      %{keys: ["F"],     desc: "Focus flyout (then j/k navigate, Enter open, Esc exit)"},
    ]},
    %{group: "context", label: "Page-specific", scope_note: "Route-dependent", bindings: [
      %{keys: ["f", "f"], desc: "Toggle filter drawer (tasks page)"},
      %{keys: ["a", "d"], desc: "Toggle agent drawer (chat page)"},
      %{keys: ["m", "b"], desc: "Toggle members panel (chat page)"},
      %{keys: ["i"],      desc: "Focus composer (DM page)"},
    ]},
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Keybinding Reference")
     |> assign(:sidebar_tab, :keybindings)
     |> assign(:sidebar_project, nil)
     |> assign(:commands, @commands)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-3xl mx-auto space-y-8">
        <div>
          <h1 class="text-lg font-semibold text-base-content">Vim Keybinding Reference</h1>
          <p class="mt-1 text-sm text-base-content/60">
            Press <kbd class="kbd kbd-sm">?</kbd> anywhere for a filtered overlay. This page shows all bindings.
          </p>
        </div>

        <div :for={group <- @commands} class="space-y-2">
          <div class="flex items-baseline gap-3">
            <h2 class="text-xs font-semibold uppercase tracking-widest text-base-content/50">
              <%= group.label %>
            </h2>
            <span :if={Map.get(group, :scope_note)} class="text-xs text-base-content/40 italic">
              — <%= group.scope_note %>
            </span>
          </div>
          <div class="rounded-lg border border-base-300 divide-y divide-base-300 overflow-hidden">
            <div :for={b <- group.bindings} class="flex items-center justify-between px-4 py-2.5 bg-base-100 hover:bg-base-200/50">
              <span class="text-sm text-base-content/80"><%= b.desc %></span>
              <span class="flex items-center gap-1">
                <kbd :for={k <- b.keys} class="kbd kbd-sm"><%= k %></kbd>
              </span>
            </div>
          </div>
        </div>

        <p class="text-xs text-base-content/40">
          Enable vim navigation in <.link navigate={~p"/settings"} class="underline">Settings → General</.link>.
        </p>
      </div>
    </div>
    """
  end
end
