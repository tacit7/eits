defmodule EyeInTheSkyWebWeb.Components.NewSessionDrawer do
  @moduledoc """
  Reusable New Session drawer component.
  """

  use Phoenix.LiveComponent

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :selected_model, "opus")}
  end

  @impl true
  def handle_event("model_changed", %{"model" => model}, socket) do
    {:noreply, assign(socket, :selected_model, model)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="drawer drawer-end">
      <input
        id="new-session-drawer"
        type="checkbox"
        class="drawer-toggle"
        checked={@show}
        phx-click={@toggle_event}
      />
      <div class="drawer-side z-50">
        <label for="new-session-drawer" class="drawer-overlay"></label>
        <div class="menu p-6 w-96 min-h-full bg-base-100 text-base-content">
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-xl font-semibold"><%= assigns[:title] || "New Session" %></h2>
            <button phx-click={@toggle_event} class="btn btn-ghost btn-sm btn-circle">✕</button>
          </div>

          <form phx-submit={@submit_event} class="flex flex-col gap-4">
            <!-- Model Selection -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Model</span>
              </label>
              <select
                name="model"
                class="select select-bordered"
                required
                phx-change="model_changed"
                phx-target={@myself}
              >
                <option value="opus" selected={@selected_model == "opus"}>Opus 4.6 • Most capable for complex work</option>
                <option value="sonnet" selected={@selected_model == "sonnet"}>Sonnet 4.5 • Best for everyday tasks</option>
                <option value="sonnet[1m]" selected={@selected_model == "sonnet[1m]"}>Sonnet 4.5 (1M) • 1M context window</option>
                <option value="haiku" selected={@selected_model == "haiku"}>Haiku 4.5 • Fastest for quick answers</option>
              </select>
            </div>

            <!-- Effort Level (Opus only) -->
            <%= if @selected_model == "opus" do %>
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-medium">Effort Level</span>
                </label>
                <select name="effort_level" class="select select-bordered">
                  <option value="">-- Default (high) --</option>
                  <option value="low">Low • Faster and cheaper</option>
                  <option value="medium">Medium • Balanced approach</option>
                  <option value="high">High • Deeper reasoning (default)</option>
                </select>
              </div>
            <% end %>

            <!-- Working Directory (Project) -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Working Directory</span>
              </label>
              <select name="project_id" class="select select-bordered" required>
                <option value="">Select a project...</option>
                <%= for project <- @projects || [] do %>
                  <option value={project.id}><%= project.name %></option>
                <% end %>
              </select>
            </div>

            <!-- Agent Name -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Agent Name</span>
              </label>
              <input
                type="text"
                name="agent_name"
                class="input input-bordered"
                placeholder="e.g., Frontend Dev Agent"
                required
              />
            </div>

            <!-- Description -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Description</span>
              </label>
              <textarea
                name="description"
                class="textarea textarea-bordered h-24"
                placeholder="What will this session work on?"
                required
              ></textarea>
            </div>

            <!-- Actions -->
            <div class="flex gap-2 mt-4">
              <button type="submit" class="btn btn-primary flex-1"><%= assigns[:button_text] || "Create Session" %></button>
              <button type="button" phx-click={@toggle_event} class="btn btn-ghost flex-shrink-0">Cancel</button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
