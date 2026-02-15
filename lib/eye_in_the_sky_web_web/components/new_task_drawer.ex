defmodule EyeInTheSkyWebWeb.Components.NewTaskDrawer do
  @moduledoc """
  Reusable New Task drawer component for kanban board.
  """

  use Phoenix.LiveComponent

  @impl true
  def render(assigns) do
    ~H"""
    <div class="drawer drawer-end">
      <input
        id="new-task-drawer"
        type="checkbox"
        class="drawer-toggle"
        checked={@show}
        phx-click={@toggle_event}
      />
      <div class="drawer-side z-50">
        <label for="new-task-drawer" class="drawer-overlay"></label>
        <div class="menu p-6 w-96 min-h-full bg-base-100 text-base-content">
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-xl font-semibold">New Task</h2>
            <button phx-click={@toggle_event} class="btn btn-ghost btn-sm btn-circle">✕</button>
          </div>

          <form phx-submit={@submit_event} class="flex flex-col gap-4">
            <!-- Title -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Title</span>
              </label>
              <input
                type="text"
                name="title"
                class="input input-bordered"
                placeholder="Task title"
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
                placeholder="Task description (optional)"
              ></textarea>
            </div>
            
    <!-- State Selection -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Status</span>
              </label>
              <select name="state_id" class="select select-bordered" required>
                <%= for state <- @workflow_states do %>
                  <option value={state.id} selected={state.name == "todo"}>
                    {String.capitalize(state.name)}
                  </option>
                <% end %>
              </select>
            </div>
            
    <!-- Priority -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Priority</span>
              </label>
              <select name="priority" class="select select-bordered">
                <option value="0">None</option>
                <option value="1" selected>Low</option>
                <option value="2">Medium</option>
                <option value="3">High</option>
              </select>
            </div>
            
    <!-- Tags -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Tags</span>
              </label>
              <input
                type="text"
                name="tags"
                class="input input-bordered"
                placeholder="tag1, tag2, tag3"
              />
              <label class="label">
                <span class="label-text-alt">Comma-separated tags</span>
              </label>
            </div>
            
    <!-- Actions -->
            <div class="flex gap-2 mt-4">
              <button type="submit" class="btn btn-primary flex-1">Create Task</button>
              <button
                type="button"
                phx-click={@toggle_event}
                class="btn btn-ghost flex-shrink-0"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
