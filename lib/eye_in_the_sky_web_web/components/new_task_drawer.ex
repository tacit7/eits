defmodule EyeInTheSkyWebWeb.Components.NewTaskDrawer do
  @moduledoc """
  New Task modal dialog component.
  """

  use Phoenix.LiveComponent
  import EyeInTheSkyWebWeb.CoreComponents

  @impl true
  def render(assigns) do
    ~H"""
    <dialog
      id={"#{@id}-dialog"}
      class="modal"
      phx-hook="ModalDialog"
      data-open={to_string(@show)}
      data-toggle-event={@toggle_event}
    >
      <div class="modal-box w-96 max-w-lg">
        <div class="flex items-center justify-between mb-6">
          <h2 class="text-xl font-semibold">New Task</h2>
          <button phx-click={@toggle_event} class="btn btn-ghost btn-sm btn-circle">
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
        </div>

        <form id={"#{@id}-form"} phx-submit={@submit_event} class="flex flex-col gap-4">
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
              autofocus={@show}
            />
          </div>

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
              <span class="label-text-alt">Comma-separated</span>
            </label>
          </div>

          <div class="flex gap-2 mt-2">
            <button type="submit" class="btn btn-primary flex-1">Create Task</button>
            <button type="button" phx-click={@toggle_event} class="btn btn-ghost">Cancel</button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click={@toggle_event}>close</button>
      </form>
    </dialog>
    """
  end
end
