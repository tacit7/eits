defmodule EyeInTheSkyWeb.OverviewLive.Settings.SystemTab do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.OverviewLive.Settings.TabHelpers

  def render(assigns) do
    ~H"""
    <section>
      <h2 class="text-message font-semibold text-base-content/60 uppercase tracking-normal mb-4">
        System
      </h2>
      <div class="card bg-base-100 border border-base-300 shadow-sm">
        <div class="card-body p-0 divide-y divide-base-300">
          <%!-- Debug Logging --%>
          <div class="flex items-center justify-between px-5 py-4">
            <div>
              <p class="text-message font-medium text-base-content">Log Raw Claude Output</p>
              <p class="text-mini text-base-content/50 mt-0.5">
                Log raw JSONL output from Claude CLI to console
              </p>
            </div>
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              checked={@settings["log_claude_raw"] == "true"}
              phx-click="toggle_setting"
              phx-value-key="log_claude_raw"
            />
          </div>

          <div class="flex items-center justify-between px-5 py-4">
            <div>
              <p class="text-message font-medium text-base-content">Log Raw Codex Output</p>
              <p class="text-mini text-base-content/50 mt-0.5">
                Log raw output from Codex CLI to console
              </p>
            </div>
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              checked={@settings["log_codex_raw"] == "true"}
              phx-click="toggle_setting"
              phx-value-key="log_codex_raw"
            />
          </div>

          <div class="flex items-center justify-between px-5 py-4">
            <div>
              <p class="text-message font-medium text-base-content">Codex App Server Bridge</p>
              <p class="text-mini text-base-content/50 mt-0.5">
                Use the feature-flagged Codex JSON-RPC app-server backend for Codex turns
              </p>
            </div>
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              checked={@settings["codex_app_server_enabled"] == "true"}
              phx-click="toggle_setting"
              phx-value-key="codex_app_server_enabled"
            />
          </div>

          <div class="flex items-center justify-between px-5 py-4">
            <div>
              <p class="text-message font-medium text-base-content">Per-session Rate-Limit Bucket</p>
              <p class="text-mini text-base-content/50 mt-0.5">
                Per-session rate-limit bucket (Phase 2). Requires eits CLI with x-eits-session header support. Leaving off keeps the current IP-keyed bucket.
              </p>
            </div>
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              checked={@settings["rate_limit_per_session"] == "true"}
              phx-click="toggle_setting"
              phx-value-key="rate_limit_per_session"
            />
          </div>

          <%!-- Database Info --%>
          <div class="px-5 py-4">
            <p class="text-message font-medium text-base-content mb-3">Database</p>
            <div class="grid grid-cols-2 gap-x-8 gap-y-2 text-mini">
              <div class="text-base-content/50">Path</div>
              <div class="font-mono text-base-content truncate" title={@db_info.path}>
                {@db_info.path}
              </div>
              <div class="text-base-content/50">Size</div>
              <div class="text-base-content">{format_db_size(@db_info.size)}</div>
            </div>
            <div class="mt-3">
              <p class="text-mini text-base-content/50 mb-2">Table Counts</p>
              <div class="flex flex-wrap gap-2">
                <span
                  :for={{table, count} <- @db_info.table_counts}
                  class="eits-chip eits-chip--muted gap-1"
                >
                  {table}
                  <span class="font-semibold">{count}</span>
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end
end
