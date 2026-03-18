defmodule EyeInTheSkyWebWeb.Components.DmPage.Composer do
  @moduledoc false

  use EyeInTheSkyWebWeb, :html

  attr :uploads, :map, required: true
  attr :selected_model, :string, default: "opus"
  attr :selected_effort, :string, default: "medium"
  attr :show_effort_menu, :boolean, default: false
  attr :show_model_menu, :boolean, default: false
  attr :processing, :boolean, default: false
  attr :slash_items, :list, default: []
  attr :thinking_enabled, :boolean, default: false
  attr :max_budget_usd, :any, default: nil
  attr :provider, :string, default: "claude"
  attr :total_tokens, :integer, default: 0
  attr :total_cost, :float, default: 0.0
  attr :context_used, :integer, default: 0
  attr :context_window, :integer, default: 0

  def message_form(assigns) do
    ~H"""
    <form
      phx-submit="send_message"
      phx-change="validate_upload"
      class="rounded-2xl border border-base-content/10 bg-base-200 shadow-sm outline-none"
      id="message-form"
      data-slash-items={Jason.encode!(@slash_items)}
      phx-hook="DmComposer"
    >
      <%!-- Upload previews --%>
      <%= if @uploads.files.entries != [] do %>
        <div class="px-4 pt-3 flex flex-wrap gap-2" id="upload-preview-list">
          <%= for entry <- @uploads.files.entries do %>
            <div class="flex items-center gap-2 rounded-lg bg-base-content/[0.04] px-3 py-1.5 text-xs">
              <.icon name="hero-paper-clip" class="w-3.5 h-3.5 text-base-content/40" />
              <span class="text-base-content/70">{entry.client_name}</span>
              <span class="text-base-content/30">{format_size(entry.client_size)}</span>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                class="text-base-content/30 hover:text-error transition-colors"
                id={"cancel-upload-#{entry.ref}"}
              >
                <.icon name="hero-x-mark-mini" class="w-3.5 h-3.5" />
              </button>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Textarea --%>
      <div class="px-4 pt-3 pb-1">
        <textarea
          name="body"
          rows="1"
          placeholder={if @processing, do: "Queue a message...", else: "Reply..."}
          class="w-full bg-transparent border-0 outline-none focus:ring-0 text-sm resize-none min-h-[28px] max-h-40 overflow-y-auto placeholder:text-base-content/30 p-0"
          autocomplete="off"
          phx-hook="CommandHistory"
          id="message-input"
        ></textarea>
      </div>

      <%!-- Bottom toolbar --%>
      <div class="flex items-center justify-between px-3 pb-3 pt-1" id="dm-composer-toolbar">
        <%!-- Left: upload + budget + effort --%>
        <div class="flex items-center gap-2">
          <label
            for={@uploads.files.ref}
            phx-drop-target={@uploads.files.ref}
            class="flex items-center justify-center w-10 h-10 sm:w-8 sm:h-8 rounded-lg cursor-pointer text-base-content/30 hover:text-base-content/60 hover:bg-base-content/5 transition-colors"
          >
            <.icon name="hero-plus" class="w-5 h-5" />
          </label>
          <.live_file_input upload={@uploads.files} class="hidden" />
          <%!-- Budget cap input --%>
          <div class="flex items-center gap-0.5 text-xs text-base-content/40">
            <span class="font-mono">$</span>
            <input
              type="number"
              min="0"
              step="0.01"
              placeholder=""
              value={@max_budget_usd}
              phx-blur="set_max_budget"
              class="w-16 bg-transparent border-0 outline-none focus:ring-0 text-xs placeholder:text-base-content/20 font-mono p-0 [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
            />
          </div>
          <%= if @selected_model == "opus" do %>
            <div
              class="dropdown dropdown-top"
              phx-click="toggle_effort_menu"
              id="effort-selector-dropdown"
            >
              <button
                type="button"
                tabindex="0"
                class="flex items-center gap-1 px-2 py-1 rounded-lg text-xs text-base-content/50 hover:text-base-content/70 transition-colors"
                id="effort-selector-button"
              >
                <.icon name="hero-adjustments-horizontal" class="w-3.5 h-3.5" />
                <span class="font-medium">{effort_display_name(@selected_effort)}</span>
                <.icon name="hero-chevron-down-mini" class="w-3.5 h-3.5" />
              </button>
              <%= if @show_effort_menu do %>
                <ul
                  tabindex="0"
                  class="dropdown-content menu z-[1] w-52 rounded-xl border border-base-content/8 bg-base-100 p-1.5 shadow-lg"
                  id="effort-selector-menu"
                >
                  <li class="menu-title text-[10px] px-3 pt-1 pb-0.5 text-base-content/40">
                    Effort Level
                  </li>
                  <%= for {label, value, desc, icon_color} <- [
                    {"Low", "low", "Faster and cheaper", "text-success"},
                    {"Medium", "medium", "Balanced (default)", "text-info"},
                    {"High", "high", "Deeper reasoning", "text-warning"},
                    {"Max", "max", "Maximum effort", "text-error"}
                  ] do %>
                    <li>
                      <a
                        phx-click="select_effort"
                        phx-value-effort={value}
                        class={[
                          "flex items-center gap-3 rounded-lg px-3 py-2.5 hover:bg-base-content/[0.04]",
                          @selected_effort == value && "bg-base-content/[0.06]"
                        ]}
                      >
                        <.icon name="hero-adjustments-horizontal" class={"w-4 h-4 #{icon_color}"} />
                        <div>
                          <div class="text-sm font-semibold text-base-content/80">{label}</div>
                          <div class="text-[11px] text-base-content/40">{desc}</div>
                        </div>
                        <%= if @selected_effort == value do %>
                          <.icon name="hero-check-mini" class="w-4 h-4 text-primary ml-auto" />
                        <% end %>
                      </a>
                    </li>
                  <% end %>
                </ul>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Center: context used --%>
        <div class="inline-flex items-center gap-2">
          <%= if @context_window > 0 and @context_used > 0 do %>
            <% pct = Float.round(@context_used / @context_window * 100, 1) %>
            <% color_class =
              cond do
                pct < 60 -> "text-base-content/30"
                pct < 80 -> "text-warning/70"
                true -> "text-error/70"
              end %>
            <span
              class={"inline-flex items-center gap-1 text-[11px] font-mono tabular-nums " <> color_class}
              title={"#{format_number(@context_used)} / #{format_number(@context_window)} tokens used"}
            >
              {pct}% ctx
            </span>
          <% end %>
        </div>

        <%!-- Right: model selector + send/stop --%>
        <div class="flex items-center gap-2">
          <div
            class="dropdown dropdown-top dropdown-end"
            phx-click="toggle_model_menu"
            id="model-selector-dropdown"
          >
            <button
              type="button"
              tabindex="0"
              class="flex items-center gap-1 px-2 py-1 rounded-lg text-xs text-base-content/50 hover:text-base-content/70 transition-colors"
              id="model-selector-button"
            >
              <span class="font-medium">{model_display_name(@selected_model)}</span>
              <.icon name="hero-chevron-down-mini" class="w-3.5 h-3.5" />
            </button>

            <%= if @show_model_menu do %>
              <ul
                tabindex="0"
                class="dropdown-content menu z-[1] w-72 rounded-xl border border-base-content/8 bg-base-100 p-1.5 shadow-lg"
                id="model-selector-menu"
              >
                <%= if @provider == "codex" do %>
                  <li class="menu-title text-[10px] px-3 pt-1 pb-0.5 text-base-content/40">Codex</li>
                  <%= for {model, desc, color} <- [
                    {"gpt-5.4", "Latest frontier agentic coding", "text-warning"},
                    {"gpt-5.3-codex", "Frontier Codex-optimized", "text-warning"},
                    {"gpt-5.2-codex", "Frontier agentic coding", "text-info"},
                    {"gpt-5.2", "Long-running agents", "text-info"},
                    {"gpt-5.1-codex-max", "Deep and fast reasoning", "text-success"},
                    {"gpt-5.1-codex-mini", "Cheaper and faster", "text-success"}
                  ] do %>
                    <li>
                      <a
                        phx-click="select_model"
                        phx-value-model={model}
                        phx-value-effort=""
                        class="flex items-center gap-3 rounded-lg px-3 py-2.5 hover:bg-base-content/[0.04]"
                      >
                        <.icon name="hero-bolt" class={"w-4 h-4 #{color}"} />
                        <div>
                          <div class="text-sm font-semibold text-base-content/80">{model}</div>
                          <div class="text-[11px] text-base-content/40">{desc}</div>
                        </div>
                      </a>
                    </li>
                  <% end %>
                <% else %>
                  <li class="menu-title text-[10px] px-3 pt-1 pb-0.5 text-base-content/40">Claude</li>
                  <%= for {model, label, desc, color} <- [
                    {"opus", "Opus 4.6", "Most capable", "text-warning"},
                    {"opus[1m]", "Opus 4.6 (1M)", "Most capable, extended context", "text-warning"},
                    {"sonnet", "Sonnet 4.5", "Everyday tasks", "text-info"},
                    {"sonnet[1m]", "Sonnet 4.5 (1M)", "Everyday tasks, extended context", "text-info"},
                    {"haiku", "Haiku 4.5", "Fast answers", "text-success"}
                  ] do %>
                    <li>
                      <a
                        phx-click="select_model"
                        phx-value-model={model}
                        phx-value-effort=""
                        class="flex items-center gap-3 rounded-lg px-3 py-2.5 hover:bg-base-content/[0.04]"
                      >
                        <.icon name="hero-bolt" class={"w-4 h-4 #{color}"} />
                        <div>
                          <div class="text-sm font-semibold text-base-content/80">{label}</div>
                          <div class="text-[11px] text-base-content/40">{desc}</div>
                        </div>
                      </a>
                    </li>
                  <% end %>
                <% end %>
              </ul>
            <% end %>
          </div>

          <%!-- Send / Stop --%>
          <div class="flex items-center gap-1.5">
            <%= if @processing do %>
              <button
                type="submit"
                class="flex items-center justify-center w-10 h-10 sm:w-8 sm:h-8 rounded-lg bg-base-content/[0.06] text-base-content/40 hover:bg-base-content/10 transition-colors"
                id="dm-queue-button"
                title="Add to queue"
              >
                <.icon name="hero-arrow-up-mini" class="w-5 h-5" />
              </button>
              <button
                type="button"
                phx-click="kill_session"
                class="flex items-center justify-center w-10 h-10 sm:w-8 sm:h-8 rounded-lg bg-error/80 text-error-content hover:bg-error transition-colors"
                id="dm-stop-button"
              >
                <.icon name="hero-stop-solid" class="w-4 h-4" />
              </button>
            <% else %>
              <button
                type="submit"
                class="flex items-center justify-center w-10 h-10 sm:w-8 sm:h-8 rounded-lg bg-primary/70 text-primary-content hover:bg-primary transition-colors"
                id="dm-send-button"
              >
                <.icon name="hero-arrow-up-mini" class="w-5 h-5" />
              </button>
            <% end %>
          </div>
        </div>
      </div>
    </form>
    """
  end

  attr :prompts, :list, required: true

  def prompt_queue(assigns) do
    ~H"""
    <details class="group mb-2" open>
      <summary class="flex items-center gap-2 px-3 py-1.5 rounded-xl border border-base-content/8 bg-base-content/[0.02] cursor-pointer list-none hover:bg-base-content/[0.04] transition-colors select-none">
        <.icon name="hero-clock" class="w-3.5 h-3.5 text-warning/70" />
        <span class="text-[11px] font-medium text-base-content/40 flex-1 uppercase tracking-wide">
          {length(@prompts)} queued
        </span>
        <.icon name="hero-chevron-down" class="w-3 h-3 text-base-content/20" />
      </summary>
      <div class="mt-1 rounded-xl border border-base-content/8 bg-base-content/[0.02] divide-y divide-base-content/5 overflow-hidden">
        <%= for prompt <- @prompts do %>
          <div class="flex items-center gap-2 px-3 py-2">
            <span class="flex-shrink-0 text-[10px] font-mono font-medium uppercase tracking-wide px-1.5 py-0.5 rounded bg-base-content/[0.06] text-base-content/40">
              {model_display_name(prompt.context[:model] || "opus")}
            </span>
            <span class="text-xs text-base-content/50 truncate flex-1 min-w-0">
              {String.slice(prompt.message || "", 0, 80)}{if String.length(prompt.message || "") > 80,
                do: "…"}
            </span>
            <button
              type="button"
              phx-click="remove_queued_prompt"
              phx-value-id={prompt.id}
              class="flex-shrink-0 text-base-content/20 hover:text-error transition-colors"
              title="Remove from queue"
            >
              <.icon name="hero-x-mark-mini" class="w-4 h-4" />
            </button>
          </div>
        <% end %>
      </div>
    </details>
    """
  end

  defp model_display_name("opus"), do: "Opus 4.6"
  defp model_display_name("opus[1m]"), do: "Opus 4.6 (1M)"
  defp model_display_name("sonnet"), do: "Sonnet 4.5"
  defp model_display_name("sonnet[1m]"), do: "Sonnet 4.5 (1M)"
  defp model_display_name("haiku"), do: "Haiku 4.5"
  defp model_display_name("gpt-5.4"), do: "gpt-5.4"
  defp model_display_name("gpt-5.3-codex"), do: "gpt-5.3-codex"
  defp model_display_name("gpt-5.2-codex"), do: "gpt-5.2-codex"
  defp model_display_name("gpt-5.2"), do: "gpt-5.2"
  defp model_display_name("gpt-5.1-codex-max"), do: "gpt-5.1-codex-max"
  defp model_display_name("gpt-5.1-codex-mini"), do: "gpt-5.1-codex-mini"
  defp model_display_name(other), do: other

  defp effort_display_name("low"), do: "Low"
  defp effort_display_name("medium"), do: "Medium"
  defp effort_display_name("high"), do: "High"
  defp effort_display_name("max"), do: "Max"
  defp effort_display_name(_), do: "Medium"

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_number(_), do: "0"
end
