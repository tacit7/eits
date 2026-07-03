defmodule EyeInTheSkyWeb.OverviewLive.Settings.DesktopTab do
  @moduledoc false
  use Phoenix.Component

  alias EyeInTheSky.Desktop.Config, as: DesktopConfig

  def render(assigns) do
    ~H"""
    <section>
      <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
        Desktop App
      </h2>
      <div class="card bg-base-100 border border-base-300 shadow-sm">
        <div class="card-body p-0 divide-y divide-base-300">
          <div class="px-5 py-4">
            <div class="flex items-center justify-between gap-4">
              <div>
                <p class="text-sm font-medium text-base-content">Server Port</p>
                <p class="text-xs text-base-content/50 mt-0.5">
                  Port for the embedded server in the desktop app.
                  Default {DesktopConfig.default_port()}. If busy at launch, the
                  next 9 ports are tried automatically.
                </p>
              </div>
              <form phx-submit="save_desktop_port" class="flex items-center gap-2">
                <input
                  type="number"
                  name="port"
                  min="1024"
                  max="49151"
                  step="1"
                  value={@desktop_port || DesktopConfig.default_port()}
                  class="input input-bordered input-sm w-28 font-mono"
                />
                <button type="submit" class="btn btn-primary btn-sm">Save</button>
              </form>
            </div>
            <p class="text-xs text-warning mt-3">
              Takes effect the next time the desktop app is launched.
            </p>
            <p :if={!@desktop_mode?} class="text-xs text-base-content/40 mt-1">
              You're viewing this from the web app — the setting is written to
              <span class="font-mono">{DesktopConfig.config_path()}</span>
              on this machine and only affects the desktop app.
            </p>
          </div>

          <div class="px-5 py-4">
            <div class="flex items-center justify-between gap-4">
              <div>
                <p class="text-sm font-medium text-base-content">
                  Global Claude Code Integration
                </p>
                <p class="text-xs text-base-content/50 mt-0.5">
                  Installs EITS hooks into <span class="font-mono">~/.claude/settings.json</span>
                  and skills into <span class="font-mono">~/.claude/skills/</span>
                  on launch — these affect every Claude Code session on this
                  Mac, not just ones started from this app.
                </p>
              </div>
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-primary"
                checked={@hooks_consent == true}
                phx-click="toggle_hooks_consent"
                phx-value-granted={to_string(@hooks_consent != true)}
              />
            </div>
            <p class="text-xs text-warning mt-3">
              Takes effect the next time the desktop app is launched.
            </p>
            <p :if={@hooks_consent == nil} class="text-xs text-base-content/40 mt-1">
              Not yet decided — you'll be asked on first launch of the desktop app.
            </p>
          </div>
        </div>
      </div>
    </section>
    """
  end
end
