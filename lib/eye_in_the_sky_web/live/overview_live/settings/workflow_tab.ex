defmodule EyeInTheSkyWeb.OverviewLive.Settings.WorkflowTab do
  @moduledoc false
  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <section>
        <h2 class="text-message font-semibold text-base-content/60 uppercase tracking-normal mb-4">
          Workflow
        </h2>
        <div class="eits-panel bg-base-100 border border-base-300 shadow-sm">
          <div class="eits-panel__body p-0 divide-y divide-base-300">
            <div class="flex items-center justify-between px-5 py-4">
              <div>
                <p class="text-message font-medium text-base-content">EITS Workflow</p>
                <p class="text-mini text-base-content/50 mt-0.5">
                  Enable EITS hook workflow (pre-tool-use, post-commit, session-start, etc.)
                </p>
              </div>
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-primary"
                checked={@settings["eits_workflow_enabled"] == "true"}
                phx-click="toggle_setting"
                phx-value-key="eits_workflow_enabled"
              />
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end
end
