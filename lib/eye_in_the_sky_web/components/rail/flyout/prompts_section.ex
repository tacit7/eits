defmodule EyeInTheSkyWeb.Components.Rail.Flyout.PromptsSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :prompt_search, :string, default: ""
  attr :prompt_scope, :string, default: "all"
  attr :myself, :any, required: true

  def prompts_filters(assigns) do
    ~H"""
    <div class="px-2.5 py-2 border-b border-base-content/8 flex flex-col gap-2">
      <%!-- Search --%>
      <div class="relative">
        <span class="absolute left-2 top-1/2 -translate-y-1/2 text-base-content/30 pointer-events-none">
          <.icon name="hero-magnifying-glass-mini" class="size-3" />
        </span>
        <input
          type="text"
          value={@prompt_search}
          placeholder="Search prompts…"
          phx-keyup="update_prompt_search"
          phx-target={@myself}
          phx-debounce="200"
          class="w-full pl-6 pr-2 py-1 text-xs bg-base-content/5 border border-base-content/10 rounded focus:outline-none focus:border-primary/40 placeholder:text-base-content/30"
        />
      </div>

      <%!-- Scope pills --%>
      <div class="flex items-center gap-0.5">
        <.scope_pill label="All" value="all" current={@prompt_scope} myself={@myself} />
        <.scope_pill label="Global" value="global" current={@prompt_scope} myself={@myself} />
        <.scope_pill label="Project" value="project" current={@prompt_scope} myself={@myself} />
      </div>
    </div>
    """
  end

  attr :prompts, :list, default: []
  attr :prompt_search, :string, default: ""
  attr :prompt_scope, :string, default: "all"
  attr :sidebar_project, :any, default: nil

  def prompts_content(assigns) do
    ~H"""
    <.prompt_row :for={p <- @prompts} prompt={p} sidebar_project={@sidebar_project} />
    <%= if @prompts == [] do %>
      <% filtering = @prompt_search != "" or @prompt_scope != "all" %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">
        {if filtering, do: "No matching prompts", else: "No prompts"}
      </div>
    <% end %>
    """
  end

  attr :prompt, :map, required: true
  attr :sidebar_project, :any, default: nil

  defp prompt_row(assigns) do
    assigns =
      assign(assigns, :href, prompt_href(assigns.prompt, assigns.sidebar_project))

    ~H"""
    <.link
      navigate={@href}
      data-vim-flyout-item
      class="flex flex-col gap-0.5 px-3 py-2 text-xs text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50 [&.vim-nav-focused]:rounded"
    >
      <div class="flex items-center gap-1.5 min-w-0">
        <.icon name="hero-document-text" class="size-3 flex-shrink-0 text-base-content/30" />
        <span class="truncate font-medium text-base-content/80">{@prompt.name || @prompt.slug}</span>
        <span :if={is_nil(@prompt.project_id)} class="text-micro text-base-content/30 flex-shrink-0">
          global
        </span>
      </div>
      <span :if={@prompt.description && @prompt.description != ""}
            class="truncate text-base-content/40 ml-[18px]">
        {@prompt.description}
      </span>
    </.link>
    """
  end

  defp prompt_href(%{project_id: project_id} = prompt, _sidebar_project)
       when not is_nil(project_id) do
    "/projects/#{project_id}/prompts/#{prompt.id}"
  end

  defp prompt_href(prompt, %{id: project_id}) when not is_nil(project_id) do
    "/projects/#{project_id}/prompts/#{prompt.id}"
  end

  defp prompt_href(_prompt, _), do: "/prompts"

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :current, :string, default: "all"
  attr :myself, :any, required: true

  defp scope_pill(assigns) do
    ~H"""
    <% active = @current == @value %>
    <button
      phx-click="set_prompt_scope"
      phx-value-scope={@value}
      phx-target={@myself}
      class={[
        "text-nano px-1.5 py-0.5 rounded transition-colors",
        if(active,
          do: "bg-primary/15 text-primary font-medium",
          else: "text-base-content/45 hover:text-base-content/70 hover:bg-base-content/8"
        )
      ]}
    >
      {@label}
    </button>
    """
  end
end
