defmodule EyeInTheSkyWeb.Components.Rail.Modals.RailModal do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :modal, :atom, required: true
  attr :myself, :any, required: true

  def rail_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-[100] flex items-center justify-center bg-black/40">
      <div class="bg-base-100 border border-base-content/10 rounded-lg shadow-xl w-72 p-4 flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <span class="text-sm font-semibold text-base-content/80">
            {if @modal == :new_task, do: "New Task", else: "New Prompt"}
          </span>
          <button
            type="button"
            phx-click="close_rail_modal"
            phx-target={@myself}
            class="size-5 flex items-center justify-center rounded text-base-content/40 hover:text-base-content/70 hover:bg-base-content/8 transition-colors"
          >
            <.icon name="hero-x-mark-mini" class="size-3.5" />
          </button>
        </div>

        <form phx-submit="submit_rail_modal" phx-target={@myself} class="flex flex-col gap-2">
          <input
            type="text"
            name="title"
            placeholder="Title"
            autofocus
            required
            class="w-full px-2.5 py-1.5 text-sm bg-base-content/5 border border-base-content/10 rounded focus:outline-none focus:border-primary/40 placeholder:text-base-content/30"
          />
          <textarea
            name="body"
            placeholder="Body (optional)"
            rows="3"
            class="w-full px-2.5 py-1.5 text-sm bg-base-content/5 border border-base-content/10 rounded focus:outline-none focus:border-primary/40 placeholder:text-base-content/30 resize-none"
          ></textarea>

          <div class="flex items-center justify-end gap-2">
            <button
              type="button"
              phx-click="close_rail_modal"
              phx-target={@myself}
              class="px-3 py-1 text-xs text-base-content/55 hover:text-base-content/80 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="px-3 py-1 text-xs bg-primary text-primary-content rounded hover:opacity-90 transition-opacity font-medium"
            >
              Create
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
