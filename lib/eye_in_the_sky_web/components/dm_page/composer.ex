defmodule EyeInTheSkyWeb.Components.DmPage.Composer do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Components.DmHelpers
  alias EyeInTheSkyWeb.DmLive.SlashCommands
  alias EyeInTheSkyWeb.Helpers.FileHelpers
  alias EyeInTheSkyWeb.Helpers.ModelHelpers

  attr :uploads, :map, required: true
  attr :selected_model, :string, default: "claude-opus-4-7"
  attr :selected_effort, :string, default: "medium"
  attr :active_overlay, :any, default: nil
  attr :processing, :boolean, default: false
  attr :slash_items, :list, default: []
  attr :thinking_enabled, :boolean, default: false
  attr :max_budget_usd, :any, default: nil
  attr :provider, :string, default: "claude"
  attr :context_used, :integer, default: 0
  attr :context_window, :integer, default: 0
  attr :total_cost, :float, default: 0.0
  attr :display_name, :string, default: nil
  attr :session_cli_opts, :list, default: []
  attr :session_uuid, :string, default: nil

  def message_form(assigns) do
    ~H"""
    <form
      phx-submit="send_message"
      phx-change="validate_upload"
      class="rounded-2xl border border-[var(--border-subtle)] focus-within:border-primary/40 bg-[var(--surface-composer)] shadow-sm outline-none transition-colors"
      id="message-form"
      data-slash-items={Jason.encode!(@slash_items)}
      data-session-flags={Jason.encode!(serialize_cli_opts(@session_cli_opts))}
      phx-hook="DmComposer"
    >
      <%!-- Upload previews --%>
      <%= if @uploads.files.entries != [] do %>
        <div class="px-4 pt-3 flex flex-wrap gap-2" id="upload-preview-list">
          <%= for entry <- @uploads.files.entries do %>
            <div class="flex items-center gap-2 rounded-lg bg-base-content/[0.04] px-3 py-1.5 text-xs">
              <.icon name="hero-paper-clip" class="size-3.5 text-base-content/40" />
              <span class="text-base-content/70">{entry.client_name}</span>
              <span class="text-base-content/30">{FileHelpers.format_size(entry.client_size)}</span>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                class="text-base-content/30 hover:text-error transition-colors min-w-[44px] min-h-[44px]"
                id={"cancel-upload-#{entry.ref}"}
              >
                <.icon name="hero-x-mark-mini" class="size-3.5" />
              </button>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Textarea --%>
      <div class="px-3 pt-2 pb-1">
        <textarea
          name="body"
          rows="1"
          placeholder={
            cond do
              @processing -> "Queue a message…"
              @display_name -> "Reply to #{@display_name}…"
              true -> "Reply…"
            end
          }
          class="w-full bg-transparent border-0 outline-none focus:ring-0 text-[13px] resize-none min-h-[56px] max-h-40 overflow-y-auto placeholder:text-base-content/30 p-0 leading-relaxed"
          autocomplete="off"
          phx-hook="CommandHistory"
          id="message-input"
          data-session-uuid={@session_uuid}
          data-vim-composer
        ></textarea>
      </div>

      <%!-- Format bar — hidden until Aa is clicked --%>
      <div id="format-bar" class="hidden px-3 pb-1 flex items-center gap-0.5">
        <button
          type="button"
          data-fmt="bold"
          title="Bold"
          class="flex items-center justify-center w-7 h-7 rounded text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 transition-colors"
        >
          <span class="font-bold text-sm leading-none">B</span>
        </button>
        <button
          type="button"
          data-fmt="italic"
          title="Italic"
          class="flex items-center justify-center w-7 h-7 rounded text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 transition-colors"
        >
          <span class="italic text-sm leading-none">I</span>
        </button>
        <button
          type="button"
          data-fmt="strike"
          title="Strikethrough"
          class="flex items-center justify-center w-7 h-7 rounded text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 transition-colors"
        >
          <span class="line-through text-sm leading-none">S</span>
        </button>
        <div class="w-px h-4 bg-base-content/10 mx-0.5"></div>
        <button
          type="button"
          data-fmt="code"
          title="Inline code"
          class="flex items-center justify-center w-7 h-7 rounded text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 transition-colors"
        >
          <.icon name="hero-code-bracket" class="size-3.5" />
        </button>
        <button
          type="button"
          data-fmt="code-block"
          title="Code block"
          class="flex items-center justify-center w-7 h-7 rounded text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 transition-colors"
        >
          <span class="font-mono text-micro leading-none tracking-tight">```</span>
        </button>
        <div class="w-px h-4 bg-base-content/10 mx-0.5"></div>
        <button
          type="button"
          data-fmt="link"
          title="Link"
          class="flex items-center justify-center w-7 h-7 rounded text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 transition-colors"
        >
          <.icon name="hero-link" class="size-3.5" />
        </button>
      </div>

      <%!-- Bottom toolbar --%>
      <div class="flex items-center gap-2 px-3 pb-2 pt-1 mt-1" id="dm-composer-toolbar">
        <%!-- Left: upload + format toggle + budget + effort --%>
        <div class="flex items-center gap-1.5">
          <label
            for={@uploads.files.ref}
            phx-drop-target={@uploads.files.ref}
            class="flex items-center justify-center w-11 h-11 sm:w-8 sm:h-8 rounded-lg cursor-pointer text-base-content/30 hover:text-base-content/60 hover:bg-base-content/5 transition-colors"
          >
            <.icon name="hero-plus" class="size-5" />
          </label>
          <button
            type="button"
            id="formatter-toggle"
            title="Format text"
            class="flex items-center justify-center w-11 h-11 sm:w-8 sm:h-8 rounded-lg text-base-content/30 hover:text-base-content/60 hover:bg-base-content/5 transition-colors"
          >
            <span class="text-xs font-semibold tracking-tight select-none">Aa</span>
          </button>
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
          <%= if String.starts_with?(@selected_model, "claude-opus") or @selected_model in ["opus", "opus[1m]"] do %>
            <div
              class="dropdown dropdown-top"
              phx-click="toggle_effort_menu"
              id="effort-selector-dropdown"
            >
              <button
                type="button"
                tabindex="0"
                class="flex items-center gap-1.5 px-2 h-6 rounded-md text-[11px] font-medium text-base-content/55 bg-base-content/[0.05] border border-[var(--border-subtle)] hover:text-base-content/75 hover:bg-base-content/[0.08] transition-colors"
                id="effort-selector-button"
              >
                <.icon name="hero-adjustments-horizontal" class="size-3" />
                <span>{DmHelpers.effort_display_name(@selected_effort)}</span>
                <.icon name="hero-chevron-down-mini" class="size-3 flex-shrink-0" />
              </button>
              <%= if @active_overlay == :effort_menu do %>
                <ul
                  tabindex="0"
                  class="dropdown-content menu z-[1] w-48 rounded-xl border border-base-content/8 bg-base-100 p-1.5 shadow-lg"
                  id="effort-selector-menu"
                >
                  <li class="menu-title text-xs px-3 pt-1 pb-0.5 text-base-content/40">
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
                        <.icon name="hero-adjustments-horizontal" class={"size-4 #{icon_color}"} />
                        <div>
                          <div class="text-sm font-semibold text-base-content/80">{label}</div>
                          <div class="text-mini text-base-content/40">{desc}</div>
                        </div>
                        <%= if @selected_effort == value do %>
                          <.icon name="hero-check-mini" class="size-4 text-primary ml-auto" />
                        <% end %>
                      </a>
                    </li>
                  <% end %>
                </ul>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Center: context meter --%>
        <div class="inline-flex items-center gap-2">
          <%= if @context_window > 0 and @context_used > 0 do %>
            <.context_meter
              context_used={@context_used}
              context_window={@context_window}
              total_cost={@total_cost}
              active_overlay={@active_overlay}
            />
          <% end %>
        </div>

        <%!-- Right: model selector + send/stop --%>
        <div class="flex items-center gap-2 ml-auto">
          <div
            class="dropdown dropdown-top dropdown-end"
            phx-click="toggle_model_menu"
            id="model-selector-dropdown"
          >
            <button
              type="button"
              tabindex="0"
              class="flex items-center gap-1.5 px-2 h-6 rounded-md text-[11px] font-medium text-base-content/55 bg-base-content/[0.05] border border-[var(--border-subtle)] hover:text-base-content/75 hover:bg-base-content/[0.08] transition-colors"
              id="model-selector-button"
            >
              <span class="w-[5px] h-[5px] rounded-full bg-primary/60 flex-shrink-0"></span>
              <span>{model_display_name(@selected_model)}</span>
              <.icon name="hero-chevron-down-mini" class="size-3 flex-shrink-0" />
            </button>

            <%= if @active_overlay == :model_menu do %>
              <ul
                tabindex="0"
                class="dropdown-content menu z-[1] w-72 rounded-xl border border-base-content/8 bg-base-100 p-1.5 shadow-lg"
                id="model-selector-menu"
              >
                <%= cond do %>
                  <% @provider == "codex" -> %>
                    <li class="menu-title text-xs px-3 pt-1 pb-0.5 text-base-content/40">Codex</li>
                    <%= for {model, label, desc, color} <- ModelHelpers.codex_models_with_meta() do %>
                      <li>
                        <a
                          phx-click="select_model"
                          phx-value-model={model}
                          phx-value-effort=""
                          class="flex items-center gap-3 rounded-lg px-3 py-2.5 hover:bg-base-content/[0.04]"
                        >
                          <.icon name="hero-bolt" class={"size-4 #{color}"} />
                          <div>
                            <div class="text-sm font-semibold text-base-content/80">{label}</div>
                            <div class="text-mini text-base-content/40">{desc}</div>
                          </div>
                        </a>
                      </li>
                    <% end %>
                  <% @provider == "gemini" -> %>
                    <li class="menu-title text-xs px-3 pt-1 pb-0.5 text-base-content/40">Gemini</li>
                    <%= for {model, label, desc, color} <- ModelHelpers.gemini_models_with_meta() do %>
                      <li>
                        <a
                          phx-click="select_model"
                          phx-value-model={model}
                          phx-value-effort=""
                          class="flex items-center gap-3 rounded-lg px-3 py-2.5 hover:bg-base-content/[0.04]"
                        >
                          <.icon name="hero-sparkles" class={"size-4 #{color}"} />
                          <div>
                            <div class="text-sm font-semibold text-base-content/80">{label}</div>
                            <div class="text-mini text-base-content/40">{desc}</div>
                          </div>
                        </a>
                      </li>
                    <% end %>
                  <% true -> %>
                    <li class="menu-title text-xs px-3 pt-1 pb-0.5 text-base-content/40">Claude</li>
                    <%= for {model, label, desc, color} <- ModelHelpers.claude_models_with_meta() do %>
                      <li>
                        <a
                          phx-click="select_model"
                          phx-value-model={model}
                          phx-value-effort=""
                          class="flex items-center gap-3 rounded-lg px-3 py-2.5 hover:bg-base-content/[0.04]"
                        >
                          <.icon name="hero-bolt" class={"size-4 #{color}"} />
                          <div>
                            <div class="text-sm font-semibold text-base-content/80">{label}</div>
                            <div class="text-mini text-base-content/40">{desc}</div>
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
                class="flex items-center gap-1.5 px-3 h-7 rounded-lg bg-base-content/[0.06] text-base-content/40 hover:bg-base-content/10 transition-colors text-[12px] font-semibold"
                id="dm-queue-button"
                title="Add to queue"
              >
                Queue
                <kbd class="text-[10px] font-mono opacity-55 leading-none">↵</kbd>
              </button>
              <button
                type="button"
                phx-click="kill_session"
                class="flex items-center gap-1.5 px-3 h-7 rounded-lg bg-error/80 text-error-content hover:bg-error transition-colors text-[12px] font-semibold"
                id="dm-stop-button"
              >
                <.icon name="hero-stop-solid" class="size-3.5" />
                Stop
              </button>
            <% else %>
              <button
                type="submit"
                class="flex items-center gap-1.5 px-3 h-7 rounded-lg bg-primary/80 text-primary-content hover:bg-primary transition-colors text-[12px] font-semibold"
                id="dm-send-button"
              >
                Send
                <kbd class="text-[10px] font-mono opacity-55 leading-none">↵</kbd>
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
        <.icon name="hero-clock" class="size-3.5 text-warning/70" />
        <span class="text-mini font-medium text-base-content/40 flex-1 uppercase tracking-wide">
          {length(@prompts)} queued
        </span>
        <.icon name="hero-chevron-down" class="size-3 text-base-content/20" />
      </summary>
      <div class="mt-1 rounded-xl border border-base-content/8 bg-base-content/[0.02] divide-y divide-base-content/5 overflow-hidden">
        <%= for prompt <- @prompts do %>
          <div class="flex items-center gap-2 px-3 py-2">
            <span class="flex-shrink-0 text-xs font-mono font-medium uppercase tracking-wide px-1.5 py-0.5 rounded bg-base-content/[0.06] text-base-content/40">
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
              <.icon name="hero-x-mark-mini" class="size-4" />
            </button>
          </div>
        <% end %>
      </div>
    </details>
    """
  end

  # ─── Context meter ──────────────────────────────────────────────────────────

  attr :context_used, :integer, required: true
  attr :context_window, :integer, required: true
  attr :total_cost, :float, default: 0.0
  attr :active_overlay, :any, default: nil

  defp context_meter(assigns) do
    ratio = min(assigns.context_used / assigns.context_window, 1.0)
    pct = ratio * 100.0

    # Segment shares (claudette visual fiction: 8% system, 7% files, rest convo)
    scale = min(1.0, ratio / 0.15)
    system_share = 0.08 * scale
    files_share = 0.07 * scale
    conv_share = max(0.0, ratio - system_share - files_share)

    # Color band
    {bar_color, label_color} =
      cond do
        pct < 60 -> {"bg-base-content/25", "text-base-content/30"}
        pct < 85 -> {"bg-warning/70", "text-warning/70"}
        true -> {"bg-error/70", "text-error/70"}
      end

    # 10-cell bar fill
    filled_float = ratio * 10.0
    filled_floor = trunc(filled_float)
    partial_frac = filled_float - filled_floor

    assigns =
      assigns
      |> Map.put(:ratio, ratio)
      |> Map.put(:pct, pct)
      |> Map.put(:system_share, system_share)
      |> Map.put(:files_share, files_share)
      |> Map.put(:conv_share, conv_share)
      |> Map.put(:bar_color, bar_color)
      |> Map.put(:label_color, label_color)
      |> Map.put(:filled_floor, filled_floor)
      |> Map.put(:partial_frac, partial_frac)

    ~H"""
    <div class="relative dropdown dropdown-top">
      <%!-- Trigger: 10-cell segmented meter --%>
      <button
        type="button"
        phx-click="toggle_context_meter"
        class={"flex items-end gap-px h-3.5 cursor-pointer group " <> @label_color}
        title={"#{format_number(@context_used)} / #{format_number(@context_window)} tokens — click for details"}
        aria-label="Context window usage"
      >
        <%= for i <- 0..9 do %>
          <span class={[
            "w-[3px] rounded-sm transition-colors",
            cond do
              i < @filled_floor ->
                "h-full " <> @bar_color
              i == @filled_floor and @partial_frac > 0.02 ->
                "relative h-full bg-base-content/10 overflow-hidden"
              true ->
                "h-full bg-base-content/10"
            end
          ]}>
            <%= if i == @filled_floor and @partial_frac > 0.02 do %>
              <span
                class={"absolute bottom-0 left-0 right-0 " <> @bar_color}
                style={"height: #{round(@partial_frac * 100)}%"}
              />
            <% end %>
          </span>
        <% end %>
      </button>

      <%!-- Popover --%>
      <%= if @active_overlay == :context_meter do %>
        <div
          class="dropdown-content z-50 mb-2 w-64 rounded-xl border border-base-content/10 bg-base-100 shadow-xl p-4"
          role="dialog"
          aria-label="Context window details"
        >
          <%!-- Header --%>
          <div class="flex items-center justify-between mb-3">
            <span class="text-xs font-semibold uppercase tracking-wider text-base-content/40">
              Context
            </span>
            <span class={"text-xs font-mono font-semibold " <> @label_color}>
              {round(@pct)}% used
            </span>
          </div>

          <%!-- Segmented bar (3-segment continuous) --%>
          <div class="flex h-1.5 rounded-full overflow-hidden mb-2 bg-base-content/[0.06]">
            <%= if @system_share > 0 do %>
              <span
                class="bg-base-content/30 h-full"
                style={"width: #{round(@system_share * 100)}%"}
                title="System + tools"
              />
            <% end %>
            <%= if @conv_share > 0 do %>
              <span
                class={"h-full " <> @bar_color}
                style={"width: #{round(@conv_share * 100)}%"}
                title="Conversation"
              />
            <% end %>
            <%= if @files_share > 0 do %>
              <span
                class="bg-info/50 h-full"
                style={"width: #{round(@files_share * 100)}%"}
                title="Latest files"
              />
            <% end %>
          </div>

          <%!-- Legend --%>
          <div class="space-y-1 mb-3">
            <div class="flex items-center justify-between text-xs text-base-content/50">
              <span class="flex items-center gap-1.5">
                <span class="w-2 h-2 rounded-sm bg-base-content/30 flex-shrink-0" />
                System + tools
              </span>
              <span class="font-mono">{format_number(round(@system_share * @context_window))}</span>
            </div>
            <div class="flex items-center justify-between text-xs text-base-content/50">
              <span class="flex items-center gap-1.5">
                <span class={"w-2 h-2 rounded-sm flex-shrink-0 " <> @bar_color} />
                Conversation
              </span>
              <span class="font-mono">{format_number(round(@conv_share * @context_window))}</span>
            </div>
            <div class="flex items-center justify-between text-xs text-base-content/50">
              <span class="flex items-center gap-1.5">
                <span class="w-2 h-2 rounded-sm bg-info/50 flex-shrink-0" />
                Latest files
              </span>
              <span class="font-mono">{format_number(round(@files_share * @context_window))}</span>
            </div>
          </div>

          <%!-- Divider --%>
          <div class="border-t border-base-content/[0.06] my-3" />

          <%!-- Token count + cost --%>
          <div class="flex items-center justify-between mb-3">
            <span class="text-xs text-base-content/40 font-mono">
              {format_number(@context_used)} / {format_number(@context_window)}
            </span>
            <%= if @total_cost > 0 do %>
              <span class="text-xs font-mono text-base-content/40">
                {format_cost(@total_cost)}
              </span>
            <% end %>
          </div>

          <%!-- Compact + Clear --%>
          <div class="flex gap-2">
            <button
              type="button"
              phx-click="send_slash_command"
              phx-value-command="/compact"
              class="flex-1 rounded-lg bg-base-content/[0.05] hover:bg-base-content/[0.09] border border-base-content/[0.08] text-xs font-medium text-base-content/60 py-1.5 transition-colors"
            >
              Compact
            </button>
            <button
              type="button"
              phx-click="send_slash_command"
              phx-value-command="/clear"
              class="flex-1 rounded-lg bg-base-content/[0.05] hover:bg-base-content/[0.09] border border-base-content/[0.08] text-xs font-medium text-base-content/60 py-1.5 transition-colors"
            >
              Clear
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_cost(cost) when cost < 0.01, do: "<$0.01"
  defp format_cost(cost) when cost < 100, do: "$#{:erlang.float_to_binary(cost, decimals: 2)}"
  defp format_cost(cost), do: "$#{round(cost)}"

  defp model_display_name(slug), do: EyeInTheSkyWeb.Helpers.ModelHelpers.model_display_name(slug)

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

  defp serialize_cli_opts(opts) do
    key_map = SlashCommands.opt_key_to_slug()

    opts
    |> Enum.reject(fn {k, _v} -> k in [:_clear, :_noop] end)
    |> Enum.flat_map(fn {k, v} ->
      slug = Map.get(key_map, Atom.to_string(k))
      if slug, do: [%{slug: slug, value: v}], else: []
    end)
  end
end
