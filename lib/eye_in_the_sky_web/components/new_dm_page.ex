defmodule EyeInTheSkyWeb.Components.NewDmPage do
  use EyeInTheSkyWeb, :html

  import EyeInTheSkyWeb.Components.DmPage.MessageComposer, only: [message_composer: 1]

  attr :uploads, :map, required: true
  attr :selected_model, :string, required: true
  attr :provider, :string, default: "claude"
  attr :selected_effort, :string, default: "medium"
  attr :active_overlay, :any, default: nil
  attr :processing, :boolean, default: false
  attr :slash_items, :list, default: []
  attr :thinking_enabled, :boolean, default: false
  attr :show_thinking_blocks, :boolean, default: false
  attr :max_budget_usd, :any, default: nil
  attr :context_used, :integer, default: 0
  attr :context_window, :integer, default: 0
  attr :total_cost, :float, default: 0.0
  attr :session_cli_opts, :list, default: []

  def new_dm_page(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-base-100">
      <div class="flex-1" />
      <div class="max-w-[860px] mx-auto w-full px-5 pb-7 pt-3 safe-inset-bottom">
        <.message_composer
          uploads={@uploads}
          selected_model={@selected_model}
          provider={@provider}
          selected_effort={@selected_effort}
          active_overlay={@active_overlay}
          processing={@processing}
          slash_items={@slash_items}
          thinking_enabled={@thinking_enabled}
          show_thinking_blocks={@show_thinking_blocks}
          max_budget_usd={@max_budget_usd}
          context_used={@context_used}
          context_window={@context_window}
          total_cost={@total_cost}
          session_cli_opts={@session_cli_opts}
        />
      </div>
    </div>
    """
  end
end
