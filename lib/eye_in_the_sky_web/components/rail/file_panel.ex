defmodule EyeInTheSkyWeb.Components.Rail.FilePanel do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :file_tabs, :list, required: true
  attr :active_tab_path, :any, required: true
  attr :myself, :any, required: true
  attr :socket, :any, required: true

  def file_panel(assigns) do
    active_tab = Enum.find(assigns.file_tabs, &(&1.path == assigns.active_tab_path))
    assigns = assign(assigns, :active_tab, active_tab)

    ~H"""
    <div
      id="file-editor-pane"
      phx-hook="EditorLayout"
      data-has-tabs={if @file_tabs == [], do: "false", else: "true"}
      class="min-w-0 flex-col border-l border-base-content/8 bg-base-100 overflow-hidden"
    >
      <%!-- Tab strip + toolbar. h-10 matches the desktop top bar in app.html.heex
           so editor content aligns with the main pane content in split mode. --%>
      <div class="flex items-center border-b border-base-content/8 bg-base-200/40 flex-shrink-0 h-10">
        <div class="flex-1 flex items-center overflow-x-auto">
          <%= for tab <- @file_tabs do %>
            <% active = tab.path == @active_tab_path %>
            <div class={[
              "flex items-center border-r border-base-content/8 flex-shrink-0",
              if(active, do: "bg-base-100", else: "bg-transparent")
            ]}>
              <button
                phx-click="file_switch_tab"
                phx-value-path={tab.path}
                phx-target={@myself}
                class={[
                  "px-3 py-1.5 text-xs truncate max-w-[160px]",
                  if(active, do: "text-base-content/90 font-medium", else: "text-base-content/45 hover:text-base-content/70")
                ]}
                title={tab.path}
              >
                {tab.name}
              </button>
              <button
                phx-click="file_close_tab"
                phx-value-path={tab.path}
                phx-target={@myself}
                class="pr-2 py-1.5 text-base-content/25 hover:text-base-content/60 transition-colors"
                title="Close"
              >
                <.icon name="hero-x-mark-mini" class="size-3" />
              </button>
            </div>
          <% end %>
        </div>
        <%!-- Split-mode toggle. Hidden unless current page allows split (CSS rule
             keyed off body[data-allow-split]). Click dispatches a window event
             handled by the EditorLayout hook. --%>
        <button
          type="button"
          phx-click={Phoenix.LiveView.JS.dispatch("editor:toggle-split", to: "body")}
          class="px-2 py-1.5 text-base-content/45 hover:text-base-content/80 transition-colors flex-shrink-0 items-center"
          data-editor-toggle
          title="Toggle split view"
          aria-label="Toggle split view"
        >
          <.icon name="hero-view-columns" class="size-4" />
        </button>
      </div>

      <%!-- Editor area or empty state --%>
      <%= if @active_tab do %>
        <div id="file-editor-relay" phx-hook="FileEditorRelay" class="hidden" />
        <%!--
          [&>div]:h-full punches height into the LiveSvelte wrapper div, which is
          auto-height by default. Without it the editor collapses to 0 height since
          the Svelte root's h-full has no anchor.
        --%>
        <div
          id={"file-editor-#{Base.url_encode64(@active_tab.path, padding: false)}"}
          phx-update="ignore"
          class="flex-1 min-w-0 overflow-hidden [&>div]:h-full"
        >
          <.svelte
            name="FileEditor"
            ssr={false}
            props={%{
              content: @active_tab.content,
              lang: @active_tab.language,
              path: @active_tab.path,
              hash: @active_tab.hash
            }}
            socket={@socket}
          />
        </div>
      <% else %>
        <div class="flex-1 flex flex-col items-center justify-center p-6 text-center text-sm text-base-content/50">
          <.icon name="hero-document-text" class="w-8 h-8 mb-2 opacity-40" />
          <p class="font-medium text-base-content/70">No file selected</p>
          <p class="mt-1">Choose a file from the file explorer to open it here.</p>
        </div>
      <% end %>
    </div>
    """
  end

  attr :section, :atom, required: true
  attr :active_section, :atom, required: true
  attr :flyout_open, :boolean, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :myself, :any, required: true

  def rail_item(assigns) do
    ~H"""
    <button
      phx-click="toggle_section"
      phx-value-section={@section}
      phx-target={@myself}
      title={@label}
      aria-label={@label}
      class={[
        "w-8 h-8 flex items-center justify-center transition-colors",
        if(@active_section == @section && @flyout_open,
          do: "bg-primary/[0.18] text-primary shadow-[inset_2px_0_0_oklch(var(--p)/0.8)]",
          else: "text-base-content/45 hover:text-base-content/80 hover:bg-base-content/8"
        )
      ]}
    >
      <%= if String.starts_with?(@icon, "lucide-") do %>
        <.custom_icon name={@icon} class="size-4" />
      <% else %>
        <.icon name={@icon} class="size-4" />
      <% end %>
    </button>
    """
  end
end
