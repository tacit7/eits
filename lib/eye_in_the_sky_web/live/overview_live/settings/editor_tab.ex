defmodule EyeInTheSkyWeb.OverviewLive.Settings.EditorTab do
  @moduledoc false
  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <section>
        <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
          External Editor
        </h2>
        <div class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body p-0 divide-y divide-base-300">
            <div class="flex items-center justify-between px-5 py-4">
              <div>
                <p class="text-sm font-medium text-base-content">Preferred Editor</p>
                <p class="text-xs text-base-content/50 mt-0.5">
                  Command used when opening files externally
                </p>
              </div>
              <form phx-change="save_setting" class="flex items-center gap-2">
                <input type="hidden" name="key" value="preferred_editor" />
                <select class="select select-bordered select-sm w-36 min-h-[44px]" name="value">
                  <%= for {label, val} <- [
                    {"VS Code", "code"}, {"Cursor", "cursor"},
                    {"vim", "vim"}, {"nano", "nano"}
                  ] do %>
                    <option value={val} selected={@settings["preferred_editor"] == val}>
                      {label}
                    </option>
                  <% end %>
                </select>
              </form>
            </div>
            <div class="flex items-center justify-between px-5 py-4">
              <div>
                <p class="text-sm font-medium text-base-content">Custom Command</p>
                <p class="text-xs text-base-content/50 mt-0.5">Override with any editor command</p>
              </div>
              <form phx-change="save_setting" class="flex items-center gap-2">
                <input type="hidden" name="key" value="preferred_editor" />
                <input
                  type="text"
                  name="value"
                  value={@settings["preferred_editor"]}
                  placeholder="e.g. code, vim, zed"
                  class="input input-bordered input-sm w-36 text-base min-h-[44px]"
                  phx-debounce="500"
                />
              </form>
            </div>
          </div>
        </div>
      </section>
      <section>
        <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
          CodeMirror
        </h2>
        <div class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body p-0 divide-y divide-base-300">
            <div class="flex items-center justify-between px-5 py-4">
              <div>
                <p class="text-sm font-medium text-base-content">Tab Size</p>
                <p class="text-xs text-base-content/50 mt-0.5">Spaces per indent level</p>
              </div>
              <form phx-change="save_setting" class="flex items-center gap-2">
                <input type="hidden" name="key" value="cm_tab_size" />
                <select class="select select-bordered select-sm w-24" name="value">
                  <option value="2" selected={(@settings["cm_tab_size"] || "2") == "2"}>2</option>
                  <option value="4" selected={@settings["cm_tab_size"] == "4"}>4</option>
                </select>
              </form>
            </div>
            <div class="flex items-center justify-between px-5 py-4">
              <div>
                <p class="text-sm font-medium text-base-content">Font Size</p>
                <p class="text-xs text-base-content/50 mt-0.5">Editor font size in pixels</p>
              </div>
              <form phx-change="save_setting" class="flex items-center gap-2">
                <input type="hidden" name="key" value="cm_font_size" />
                <select class="select select-bordered select-sm w-24" name="value">
                  <%= for size <- ["12", "13", "14", "16", "18"] do %>
                    <option value={size} selected={(@settings["cm_font_size"] || "14") == size}>
                      {size}px
                    </option>
                  <% end %>
                </select>
              </form>
            </div>
            <div class="flex items-center justify-between px-5 py-4">
              <div>
                <p class="text-sm font-medium text-base-content">Vim Keybindings</p>
                <p class="text-xs text-base-content/50 mt-0.5">Enable vim modal editing</p>
              </div>
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-primary"
                checked={@settings["cm_vim"] == "true"}
                phx-click="toggle_setting"
                phx-value-key="cm_vim"
              />
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end
end
