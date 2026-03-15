defmodule EyeInTheSkyWebWeb.Components.NewTaskDrawer do
  @moduledoc """
  New Task modal dialog component.

  Renders conditionally (not via native dialog element) to avoid DaisyUI 5's
  top-layer exit transition bug: showModal/close keeps the dialog in the
  browser top layer for ~300ms, during which the native ::backdrop blocks
  all pointer events on the page. Using a conditional div removes the element
  from the DOM entirely when closed.
  """

  use Phoenix.LiveComponent
  import EyeInTheSkyWebWeb.CoreComponents

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <%= if @show do %>
        <%!-- Backdrop --%>
        <div
          class="fixed inset-0 z-40 bg-black/30"
          phx-click={@toggle_event}
        />

        <%!-- Modal box --%>
        <div class="fixed inset-0 z-50 flex items-center justify-center p-4 pointer-events-none">
          <div class="modal-box w-96 max-w-lg pointer-events-auto">
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
        </div>
      <% end %>
    </div>
    """
  end
end
