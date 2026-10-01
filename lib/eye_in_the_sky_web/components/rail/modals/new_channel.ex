defmodule EyeInTheSkyWeb.Components.Rail.Modals.NewChannel do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  def new_channel_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-[100] flex items-center justify-center bg-black/40">
      <div class="bg-base-100 border border-base-content/10 rounded-box shadow-xl w-72 p-4 flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <span class="text-message font-semibold text-base-content/80">New Channel</span>
          <button
            type="button"
            phx-click="toggle_new_channel_form"
            class="focus-ring size-5 flex items-center justify-center rounded-box text-base-content/40 hover:text-base-content/70 hover:bg-base-content/8 transition-colors"
          >
            <.icon name="hero-x-mark-mini" class="size-3.5" />
          </button>
        </div>

        <form phx-submit="create_channel" class="flex flex-col gap-2">
          <div>
            <input
              type="text"
              name="channel_name"
              placeholder="Channel name"
              autofocus
              required
              class="focus-ring w-full px-2.5 py-1.5 text-message bg-base-content/5 border border-base-content/10 rounded-box placeholder:text-base-content/30"
            />
            <div class="text-mini text-base-content/40 mt-1">
              Use lowercase letters, numbers, and hyphens
            </div>
          </div>

          <div class="flex items-center justify-end gap-2">
            <button
              type="button"
              phx-click="toggle_new_channel_form"
              class="focus-ring px-3 py-1 text-mini text-base-content/55 hover:text-base-content/80 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="focus-ring px-3 py-1 text-mini bg-primary text-primary-content rounded-box hover:opacity-90 transition-opacity font-medium"
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
