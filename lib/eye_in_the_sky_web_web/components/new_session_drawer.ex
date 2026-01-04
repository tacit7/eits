defmodule EyeInTheSkyWebWeb.Components.NewSessionDrawer do
  @moduledoc """
  Reusable New Session drawer component.
  """

  use Phoenix.LiveComponent

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
            <h2 class="text-xl font-semibold">New Session</h2>
            <button phx-click={@toggle_event} class="btn btn-ghost btn-sm btn-circle">✕</button>
          </div>

          <form phx-submit={@submit_event} class="flex flex-col gap-4">
            <!-- Model Selection -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Model</span>
              </label>
              <select name="model" class="select select-bordered" required>
                <option value="sonnet">Sonnet</option>
                <option value="haiku">Haiku</option>
                <option value="opus">Opus</option>
              </select>
            </div>

            <!-- Project Selection or Display -->
            <%= if @projects do %>
              <!-- Project dropdown (for pages without fixed project) -->
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-medium">Project</span>
                </label>
                <select name="project_id" class="select select-bordered" required>
                  <option value="">Select a project...</option>
                  <%= for project <- @projects do %>
                    <option value={project.id}><%= project.name %></option>
                  <% end %>
                </select>
                <label class="label">
                  <span class="label-text-alt">Sets the working directory for Claude Code</span>
                </label>
              </div>
            <% else %>
              <!-- Project display (for project-specific pages) -->
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-medium">Project</span>
                </label>
                <input
                  type="text"
                  value={@current_project.name}
                  class="input input-bordered"
                  disabled
                />
                <label class="label">
                  <span class="label-text-alt">Working directory: <%= @current_project.path %></span>
                </label>
              </div>
            <% end %>

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
              <button type="submit" class="btn btn-primary flex-1">Create Session</button>
              <button type="button" phx-click={@toggle_event} class="btn btn-ghost flex-shrink-0">Cancel</button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
