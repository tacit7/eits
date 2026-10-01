defmodule EyeInTheSkyWeb.OverviewLive.Settings.GeneralTab do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents
  import EyeInTheSkyWeb.OverviewLive.Settings.TabHelpers
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]
  alias EyeInTheSkyWeb.Helpers.ModelHelpers

  def render(assigns) do
    ~H"""
    <div id="settings-general-panel" class="border-t border-base-content/10">
      <div class="grid gap-4 border-b border-base-content/10 py-5 sm:grid-cols-[minmax(0,1fr)_minmax(13rem,22rem)] sm:items-center sm:gap-8 lg:py-6">
        <div class="min-w-0">
          <p class="text-message font-semibold text-base-content">Theme</p>
          <p class="mt-1 text-message text-base-content/50">
            App-wide color theme for long monitoring sessions
          </p>
        </div>
        <div class="flex flex-wrap gap-2 sm:justify-end">
          <button
            :for={{val, label} <- @themes}
            phx-click="set_theme"
            phx-value-theme={val}
            class={[
              "eits-action h-9 min-h-0 px-3",
              if(@settings["theme"] == val,
                do: "eits-action--primary",
                else: "eits-action--secondary"
              )
            ]}
          >
            {label}
          </button>
        </div>
      </div>

      <div class="grid gap-4 border-b border-base-content/10 py-5 sm:grid-cols-[minmax(0,1fr)_minmax(13rem,22rem)] sm:items-center sm:gap-8 lg:py-6">
        <div class="min-w-0">
          <p class="text-message font-semibold text-base-content">Default Model</p>
          <p class="mt-1 text-message text-base-content/50">
            Model used when spawning new agents and sessions
          </p>
        </div>
        <div class="flex items-center gap-2 sm:justify-end">
          <form phx-change="save_setting" class="min-w-0 flex-1 sm:max-w-72">
            <input type="hidden" name="key" value="default_model" />
            <select class="select select-bordered select-sm min-h-10 w-full" name="value">
              <option
                :for={{val, label} <- @models}
                value={val}
                selected={ModelHelpers.normalize_model_alias(@settings["default_model"]) == val}
              >
                {label}
              </option>
            </select>
          </form>
          <button
            :if={!default?(@settings, "default_model")}
            phx-click="reset_setting"
            phx-value-key="default_model"
            class="eits-action eits-action--ghost eits-action--icon h-10 min-h-0 min-w-10"
            title="Reset to default"
          >
            <.icon name="hero-arrow-uturn-left" class="size-3.5" />
          </button>
        </div>
      </div>

      <div class="grid gap-4 border-b border-base-content/10 py-5 sm:grid-cols-[minmax(0,1fr)_minmax(13rem,22rem)] sm:items-center sm:gap-8 lg:py-6">
        <div class="min-w-0">
          <p class="text-message font-semibold text-base-content">CLI Idle Timeout</p>
          <p class="mt-1 text-message text-base-content/50">
            How long before an idle Claude process is killed. 0 means no timeout.
          </p>
        </div>
        <div class="flex items-center gap-2 sm:justify-end">
          <form phx-change="save_setting" class="flex items-center gap-2">
            <input type="hidden" name="key" value="cli_idle_timeout_ms" />
            <input
              type="number"
              name="value"
              value={ms_to_seconds(@settings["cli_idle_timeout_ms"])}
              min="0"
              max="3600"
              step="30"
              class="input input-bordered input-sm min-h-10 w-24 text-right"
              phx-debounce="500"
            />
            <span class="text-mini text-base-content/50">sec</span>
          </form>
          <button
            :if={!default?(@settings, "cli_idle_timeout_ms")}
            phx-click="reset_setting"
            phx-value-key="cli_idle_timeout_ms"
            class="eits-action eits-action--ghost eits-action--icon h-10 min-h-0 min-w-10"
            title="Reset to default"
          >
            <.icon name="hero-arrow-uturn-left" class="size-3.5" />
          </button>
        </div>
      </div>

      <div class="grid gap-4 border-b border-base-content/10 py-5 sm:grid-cols-[minmax(0,1fr)_minmax(13rem,22rem)] sm:items-center sm:gap-8 lg:py-6">
        <div class="min-w-0">
          <p class="text-message font-semibold text-base-content">TTS Voice</p>
          <p class="mt-1 text-message text-base-content/50">
            Default voice for text-to-speech notifications
          </p>
        </div>
        <div class="flex items-center gap-2 sm:justify-end">
          <form phx-change="save_setting" class="min-w-0 flex-1 sm:max-w-72">
            <input type="hidden" name="key" value="tts_voice" />
            <select class="select select-bordered select-sm min-h-10 w-full" name="value">
              <option :for={v <- @voices} value={v} selected={@settings["tts_voice"] == v}>
                {v}
              </option>
            </select>
          </form>
          <button
            :if={!default?(@settings, "tts_voice")}
            phx-click="reset_setting"
            phx-value-key="tts_voice"
            class="eits-action eits-action--ghost eits-action--icon h-10 min-h-0 min-w-10"
            title="Reset to default"
          >
            <.icon name="hero-arrow-uturn-left" class="size-3.5" />
          </button>
        </div>
      </div>

      <div class="grid gap-4 border-b border-base-content/10 py-5 sm:grid-cols-[minmax(0,1fr)_minmax(13rem,22rem)] sm:items-center sm:gap-8 lg:py-6">
        <div class="min-w-0">
          <p class="text-message font-semibold text-base-content">TTS Rate</p>
          <p class="mt-1 text-message text-base-content/50">Speech rate in words per minute</p>
        </div>
        <div class="flex items-center gap-2 sm:justify-end">
          <form phx-change="save_setting">
            <input type="hidden" name="key" value="tts_rate" />
            <input
              type="number"
              name="value"
              value={@settings["tts_rate"]}
              min="90"
              max="450"
              step="10"
              class="input input-bordered input-sm min-h-10 w-24 text-right"
              phx-debounce="500"
            />
          </form>
          <span class="text-mini text-base-content/50">wpm</span>
          <button
            :if={!default?(@settings, "tts_rate")}
            phx-click="reset_setting"
            phx-value-key="tts_rate"
            class="eits-action eits-action--ghost eits-action--icon h-10 min-h-0 min-w-10"
            title="Reset to default"
          >
            <.icon name="hero-arrow-uturn-left" class="size-3.5" />
          </button>
        </div>
      </div>

      <div class="grid gap-4 border-b border-base-content/10 py-5 sm:grid-cols-[minmax(0,1fr)_minmax(13rem,22rem)] sm:items-center sm:gap-8 lg:py-6">
        <div class="min-w-0">
          <p class="text-message font-semibold text-base-content">Agent status notifications</p>
          <p class="mt-1 text-message text-base-content/50">
            Show in-app notifications when an agent starts working and when it can be resumed.
            Off by default.
          </p>
        </div>
        <div class="flex sm:justify-end">
          <input
            type="checkbox"
            class="toggle toggle-sm toggle-primary"
            checked={@settings["agent_notifications"] == "true"}
            phx-click="toggle_setting"
            phx-value-key="agent_notifications"
          />
        </div>
      </div>

      <div class="grid gap-4 border-b border-base-content/10 py-5 sm:grid-cols-[minmax(0,1fr)_minmax(13rem,22rem)] sm:items-center sm:gap-8 lg:py-6">
        <div class="min-w-0">
          <p class="text-message font-semibold text-base-content">Use PTY terminal in DM sessions</p>
          <p class="mt-1 text-message text-base-content/50">
            Replace the web chat interface with an embedded PTY terminal. Requires a page reload to
            take effect.
          </p>
        </div>
        <div class="flex sm:justify-end">
          <input
            type="checkbox"
            class="toggle toggle-sm toggle-primary"
            checked={@settings["dm_use_pty"] == "true"}
            phx-click="toggle_setting"
            phx-value-key="dm_use_pty"
          />
        </div>
      </div>

      <div class="grid gap-4 border-b border-base-content/10 py-5 sm:grid-cols-[minmax(0,1fr)_minmax(13rem,22rem)] sm:items-center sm:gap-8 lg:py-6">
        <div class="min-w-0">
          <p class="text-message font-semibold text-base-content">Vim navigation</p>
          <p class="mt-1 text-message text-base-content/50">
            Keyboard-first navigation with normal and insert modes. Press ? for help.
          </p>
        </div>
        <div class="flex sm:justify-end">
          <input
            type="checkbox"
            class="toggle toggle-sm toggle-primary"
            checked={@settings["vim_nav_enabled"] == "true"}
            phx-click="toggle_setting"
            phx-value-key="vim_nav_enabled"
          />
        </div>
      </div>

      <div class="grid gap-4 border-b border-base-content/10 py-5 sm:grid-cols-[minmax(0,1fr)_minmax(13rem,22rem)] sm:items-center sm:gap-8 lg:py-6">
        <div class="min-w-0">
          <p class="text-message font-semibold text-base-content">Command Palette Shortcut</p>
          <p class="mt-1 text-message text-base-content/50">
            Modifier key used to open the command palette with K
          </p>
        </div>
        <div class="flex items-center gap-2 sm:justify-end">
          <form phx-change="save_setting" class="min-w-0 flex-1 sm:max-w-72">
            <input type="hidden" name="key" value="palette_shortcut" />
            <select class="select select-bordered select-sm min-h-10 w-full" name="value">
              <option value="auto" selected={(@settings["palette_shortcut"] || "auto") == "auto"}>
                Auto (⌘K + Ctrl+K on Mac, Ctrl+K elsewhere)
              </option>
              <option value="ctrl" selected={@settings["palette_shortcut"] == "ctrl"}>
                Ctrl+K
              </option>
              <option value="cmd" selected={@settings["palette_shortcut"] == "cmd"}>
                ⌘K (Command)
              </option>
              <option value="alt" selected={@settings["palette_shortcut"] == "alt"}>
                Alt+K
              </option>
            </select>
          </form>
          <button
            :if={!default?(@settings, "palette_shortcut")}
            phx-click="reset_setting"
            phx-value-key="palette_shortcut"
            class="eits-action eits-action--ghost eits-action--icon h-10 min-h-0 min-w-10"
            title="Reset to default"
          >
            <.icon name="hero-arrow-uturn-left" class="size-3.5" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp ms_to_seconds(value) do
    int =
      case value do
        v when v in [nil, ""] -> 0
        v -> parse_int(v) || 0
      end

    div(int, 1000)
  end
end
