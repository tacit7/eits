defmodule EyeInTheSkyWeb.OverviewLive.Settings.GeneralTab do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents
  import EyeInTheSkyWeb.OverviewLive.Settings.TabHelpers
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]
  alias EyeInTheSkyWeb.Helpers.ModelHelpers

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <section>
        <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
          Appearance
        </h2>
        <div class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body px-5 py-4">
            <p class="text-sm font-medium text-base-content mb-3">Theme</p>
            <div class="flex flex-wrap gap-2">
              <button
                :for={{val, label} <- @themes}
                phx-click="set_theme"
                phx-value-theme={val}
                class={"btn btn-md sm:btn-sm #{if @settings["theme"] == val, do: "btn-primary", else: "btn-outline"}"}
              >
                {label}
              </button>
            </div>
          </div>
        </div>
      </section>

      <section>
        <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
          Agent Defaults
        </h2>
        <div class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body p-0 divide-y divide-base-300">
            <%!-- Default Model --%>
            <div class="flex items-center justify-between px-5 py-4">
              <div>
                <p class="text-sm font-medium text-base-content">Default Model</p>
                <p class="text-xs text-base-content/50 mt-0.5">
                  Model used when spawning new agents and sessions
                </p>
              </div>
              <div class="flex items-center gap-2">
                <form phx-change="save_setting">
                  <input type="hidden" name="key" value="default_model" />
                  <select class="select select-bordered select-sm w-36 min-h-[44px]" name="value">
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
                  class="btn btn-ghost btn-xs min-h-[44px] min-w-[44px]"
                  title="Reset to default"
                >
                  <.icon name="hero-arrow-uturn-left" class="w-3.5 h-3.5" />
                </button>
              </div>
            </div>

            <%!-- CLI Idle Timeout --%>
            <div class="flex items-center justify-between px-5 py-4">
              <div>
                <p class="text-sm font-medium text-base-content">CLI Idle Timeout</p>
                <p class="text-xs text-base-content/50 mt-0.5">
                  How long before an idle Claude process is killed (seconds). 0 = no timeout.
                </p>
              </div>
              <div class="flex items-center gap-2">
                <form phx-change="save_setting" class="flex items-center gap-2">
                  <input type="hidden" name="key" value="cli_idle_timeout_ms" />
                  <input
                    type="number"
                    name="value"
                    value={ms_to_seconds(@settings["cli_idle_timeout_ms"])}
                    min="0"
                    max="3600"
                    step="30"
                    class="input input-bordered input-sm w-24 text-right min-h-[44px]"
                    phx-debounce="500"
                  />
                  <span class="text-xs text-base-content/50">sec</span>
                </form>
                <button
                  :if={!default?(@settings, "cli_idle_timeout_ms")}
                  phx-click="reset_setting"
                  phx-value-key="cli_idle_timeout_ms"
                  class="btn btn-ghost btn-xs min-h-[44px] min-w-[44px]"
                  title="Reset to default"
                >
                  <.icon name="hero-arrow-uturn-left" class="w-3.5 h-3.5" />
                </button>
              </div>
            </div>

            <%!-- TTS Voice --%>
            <div class="flex items-center justify-between px-5 py-4">
              <div>
                <p class="text-sm font-medium text-base-content">TTS Voice</p>
                <p class="text-xs text-base-content/50 mt-0.5">
                  Default voice for text-to-speech notifications
                </p>
              </div>
              <div class="flex items-center gap-2">
                <form phx-change="save_setting">
                  <input type="hidden" name="key" value="tts_voice" />
                  <select class="select select-bordered select-sm w-36 min-h-[44px]" name="value">
                    <option :for={v <- @voices} value={v} selected={@settings["tts_voice"] == v}>
                      {v}
                    </option>
                  </select>
                </form>
                <button
                  :if={!default?(@settings, "tts_voice")}
                  phx-click="reset_setting"
                  phx-value-key="tts_voice"
                  class="btn btn-ghost btn-xs min-h-[44px] min-w-[44px]"
                  title="Reset to default"
                >
                  <.icon name="hero-arrow-uturn-left" class="w-3.5 h-3.5" />
                </button>
              </div>
            </div>

            <%!-- TTS Rate --%>
            <div class="flex items-center justify-between px-5 py-4">
              <div>
                <p class="text-sm font-medium text-base-content">TTS Rate</p>
                <p class="text-xs text-base-content/50 mt-0.5">Speech rate in words per minute</p>
              </div>
              <div class="flex items-center gap-2">
                <form phx-change="save_setting">
                  <input type="hidden" name="key" value="tts_rate" />
                  <input
                    type="number"
                    name="value"
                    value={@settings["tts_rate"]}
                    min="90"
                    max="450"
                    step="10"
                    class="input input-bordered input-sm w-24 text-right min-h-[44px]"
                    phx-debounce="500"
                  />
                </form>
                <span class="text-xs text-base-content/50">wpm</span>
                <button
                  :if={!default?(@settings, "tts_rate")}
                  phx-click="reset_setting"
                  phx-value-key="tts_rate"
                  class="btn btn-ghost btn-xs min-h-[44px] min-w-[44px]"
                  title="Reset to default"
                >
                  <.icon name="hero-arrow-uturn-left" class="w-3.5 h-3.5" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section>
        <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
          Keyboard
        </h2>
        <div class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body p-0">
            <div class="flex items-center justify-between px-5 py-4">
              <div>
                <p class="text-sm font-medium text-base-content">Command Palette Shortcut</p>
                <p class="text-xs text-base-content/50 mt-0.5">
                  Modifier key used to open the command palette with K
                </p>
              </div>
              <div class="flex items-center gap-2">
                <form phx-change="save_setting">
                  <input type="hidden" name="key" value="palette_shortcut" />
                  <select class="select select-bordered select-sm w-48 min-h-[44px]" name="value">
                    <option
                      value="auto"
                      selected={(@settings["palette_shortcut"] || "auto") == "auto"}
                    >
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
                  class="btn btn-ghost btn-xs min-h-[44px] min-w-[44px]"
                  title="Reset to default"
                >
                  <.icon name="hero-arrow-uturn-left" class="w-3.5 h-3.5" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </section>
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
