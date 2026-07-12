defmodule EyeInTheSkyWeb.Components.NewDmPage do
  use EyeInTheSkyWeb, :html

  import EyeInTheSkyWeb.Components.ModelSelector, only: [model_selector: 1]
  alias EyeInTheSkyWeb.Helpers.ModelHelpers

  attr :processing, :boolean, default: false
  attr :selected_model, :string, required: true
  attr :provider, :string, default: "claude"
  attr :selected_effort, :string, default: "medium"
  attr :active_overlay, :any, default: nil

  def new_dm_page(assigns) do
    ~H"""
    <div class="flex flex-col h-full items-center justify-center bg-base-100">
      <div class="w-full max-w-2xl px-4 flex flex-col gap-6">
        <div class="text-center">
          <h1 class="text-xl font-semibold text-base-content">New conversation</h1>
          <p class="text-sm text-base-content/40 mt-1">Send a message to start an agent session.</p>
        </div>

        <form
          phx-submit="send_message"
          class="rounded-2xl border border-[var(--border-subtle)] focus-within:border-primary/40 bg-[var(--surface-composer)] shadow-sm outline-none transition-colors"
          id="new-session-form"
        >
          <%!-- Textarea --%>
          <div class="px-3 pt-3 pb-1">
            <textarea
              id="new-session-composer"
              name="body"
              rows="3"
              placeholder="What do you want to work on?"
              class="w-full bg-transparent border-0 outline-none focus:ring-0 text-[13px] resize-none min-h-[80px] max-h-60 overflow-y-auto placeholder:text-base-content/30 p-0 leading-relaxed"
              autocomplete="off"
              disabled={@processing}
              autofocus
            ></textarea>
          </div>

          <%!-- Bottom toolbar --%>
          <div class="flex items-center gap-2 px-3 pb-2 pt-1">
            <%!-- Left: empty for now — effort/plan could go here later --%>
            <div class="flex-1" />

            <%!-- Right: model selector + send --%>
            <div class="flex items-center gap-2 ml-auto">
              <.model_selector
                id="new-session-model-selector"
                entries={ModelHelpers.entries_for_provider(@provider)}
                selected_provider={@provider}
                selected_model={@selected_model}
                allow_provider_switch?={false}
                event="select_model"
                disabled?={@processing}
                placement={:up}
              />

              <button
                type="submit"
                disabled={@processing}
                class="flex items-center justify-center gap-1.5 px-3 h-7 min-h-[44px] rounded-lg bg-primary/80 text-primary-content hover:bg-primary transition-colors text-[12px] font-semibold disabled:opacity-40"
                id="new-session-send-button"
              >
                Send <kbd class="text-[10px] font-mono opacity-55 leading-none">↵</kbd>
              </button>
            </div>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
