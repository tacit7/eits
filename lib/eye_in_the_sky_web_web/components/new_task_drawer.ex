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
        <.modal_header title="New Task" toggle_event={@toggle_event} />

        <form id={"#{@id}-form"} phx-submit={@submit_event} class="flex flex-col gap-4">
          <.form_field label="Title">
            <input
              type="text"
              name="title"
              class="input input-bordered"
              placeholder="Task title"
              required
              autofocus={@show}
            />
          </.form_field>

          <.form_field label="Description">
            <textarea
              name="description"
              class="textarea textarea-bordered h-24"
              placeholder="Task description (optional)"
            ></textarea>
          </.form_field>

          <.form_field label="Status">
            <select name="state_id" class="select select-bordered" required>
              <%= for state <- @workflow_states do %>
                <option value={state.id} selected={state.name == "todo"}>
                  {String.capitalize(state.name)}
                </option>
              <% end %>
            </select>
          </.form_field>

          <.form_field label="Priority">
            <select name="priority" class="select select-bordered">
              <option value="0">None</option>
              <option value="1" selected>Low</option>
              <option value="2">Medium</option>
              <option value="3">High</option>
            </select>
          </.form_field>

          <.form_field label="Tags">
            <input
              type="text"
              name="tags"
              class="input input-bordered"
              placeholder="tag1, tag2, tag3"
            />
            <label class="label">
              <span class="label-text-alt">Comma-separated</span>
            </label>
          </.form_field>

          <.form_actions submit_text="Create Task" cancel_event={@toggle_event} class="mt-2" />
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click={@toggle_event}>close</button>
      </form>
    </dialog>
    """
  end
end
