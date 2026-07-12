defmodule EyeInTheSkyWeb.Components.NewDmPage do
  use EyeInTheSkyWeb, :html

  attr :processing, :boolean, default: false
  attr :selected_model, :string, required: true

  def new_dm_page(assigns) do
    ~H"""
    <div class="flex flex-col h-full items-center justify-center bg-base-100">
      <div class="w-full max-w-2xl px-4 flex flex-col gap-4">
        <h1 class="text-xl font-semibold text-base-content text-center">New conversation</h1>
        <p class="text-sm text-base-content/50 text-center">
          Send a message to start an agent session.
        </p>
        <form phx-submit="send_message" class="flex flex-col gap-2">
          <textarea
            id="new-session-composer"
            name="body"
            class="textarea textarea-bordered w-full min-h-[120px] resize-none"
            placeholder="What do you want to work on?"
            disabled={@processing}
            autofocus
          ></textarea>
          <div class="flex items-center justify-between">
            <span class="text-xs text-base-content/40"><%= @selected_model %></span>
            <button type="submit" class="btn btn-primary btn-sm" disabled={@processing}>
              <%= if @processing do %>
                <span class="loading loading-spinner loading-xs"></span>
              <% else %>
                Send
              <% end %>
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
