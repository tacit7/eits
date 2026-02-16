defmodule EyeInTheSkyWebWeb.Components.NewSessionModal do
  @moduledoc """
  Centered modal dialog for creating new sessions/agents.
  Context-aware: pre-fills project when launched from a project page.
  """

  use Phoenix.LiveComponent
  import EyeInTheSkyWebWeb.CoreComponents, only: [icon: 1]

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :selected_model, "sonnet")}
  end

  @impl true
  def handle_event("model_changed", %{"model" => model}, socket) do
    {:noreply, assign(socket, :selected_model, model)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={@show} class="modal modal-open" phx-window-keydown={@toggle_event} phx-key="Escape">
        <div class="modal-box max-w-md">
          <div class="flex items-center justify-between mb-5">
            <h3 class="text-base font-semibold">{assigns[:title] || "New Agent"}</h3>
            <button phx-click={@toggle_event} class="btn btn-ghost btn-sm btn-circle">
              <.icon name="hero-x-mark-mini" class="w-4 h-4" />
            </button>
          </div>

          <form phx-submit={@submit_event} class="flex flex-col gap-4">
            <%!-- Description --%>
            <div>
              <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Description</label>
              <textarea
                name="description"
                class="textarea textarea-bordered w-full h-20 text-sm"
                placeholder="What should this agent work on?"
                required
                autofocus
                phx-mounted={Phoenix.LiveView.JS.dispatch("focus")}
              ></textarea>
            </div>

            <%!-- Project --%>
            <%= if @current_project do %>
              <input type="hidden" name="project_id" value={@current_project.id} />
              <div>
                <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Project</label>
                <div class="flex items-center gap-2 px-3 py-2.5 bg-base-200/50 rounded-lg text-sm text-base-content/70 border border-base-content/10">
                  <.icon name="hero-folder-mini" class="w-3.5 h-3.5 text-base-content/40" />
                  {@current_project.name}
                </div>
              </div>
            <% else %>
              <div>
                <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Project</label>
                <select name="project_id" class="select select-bordered w-full" required>
                  <option value="">Select project...</option>
                  <%= for project <- @projects || [] do %>
                    <option value={project.id}>{project.name}</option>
                  <% end %>
                </select>
              </div>
            <% end %>

            <%!-- Model --%>
            <div>
              <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Model</label>
              <select
                name="model"
                class="select select-bordered w-full"
                required
                phx-change="model_changed"
                phx-target={@myself}
              >
                <option value="sonnet" selected={@selected_model == "sonnet"}>
                  Sonnet 4.5
                </option>
                <option value="opus" selected={@selected_model == "opus"}>
                  Opus 4.6
                </option>
                <option value="sonnet[1m]" selected={@selected_model == "sonnet[1m]"}>
                  Sonnet 4.5 (1M)
                </option>
                <option value="haiku" selected={@selected_model == "haiku"}>
                  Haiku 4.5
                </option>
              </select>
            </div>

            <%!-- Effort (Opus only) --%>
            <%= if @selected_model == "opus" do %>
              <div>
                <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Effort</label>
                <select name="effort_level" class="select select-bordered w-full">
                  <option value="">Default</option>
                  <option value="low">Low</option>
                  <option value="medium">Medium</option>
                  <option value="high">High</option>
                </select>
              </div>
            <% end %>

            <%!-- Submit --%>
            <button type="submit" class="btn btn-primary w-full mt-2">
              {assigns[:button_text] || "Create Agent"}
            </button>
          </form>
        </div>
        <div class="modal-backdrop" phx-click={@toggle_event}></div>
      </div>
    </div>
    """
  end
end
