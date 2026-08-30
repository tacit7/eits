defmodule EyeInTheSkyWeb.Components.DmPage.MessageComposer do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  import EyeInTheSkyWeb.Components.ModelSelector, only: [model_selector: 1]
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [format_cost: 1, format_number: 1]

  alias EyeInTheSkyWeb.Components.DmHelpers
  alias EyeInTheSkyWeb.DmLive.SlashCommands
  alias EyeInTheSkyWeb.Helpers.FileHelpers
  alias EyeInTheSkyWeb.Helpers.ModelHelpers
  attr :uploads, :map, required: true
  attr :selected_model, :string, default: "claude-opus-4-8"
  attr :selected_effort, :string, default: "medium"
  attr :active_overlay, :any, default: nil
  attr :processing, :boolean, default: false
  attr :slash_items, :list, default: []
  attr :thinking_enabled, :boolean, default: false
  attr :show_thinking_blocks, :boolean, default: false
  attr :max_budget_usd, :any, default: nil
  attr :provider, :string, default: "claude"
  attr :context_used, :integer, default: 0
  attr :context_window, :integer, default: 0
  attr :total_cost, :float, default: 0.0
  attr :display_name, :string, default: nil
  attr :session_cli_opts, :list, default: []
  attr :session_uuid, :string, default: nil

  def message_composer(assigns) do
    selected_model = composer_selected_model(assigns.provider, assigns.selected_model)

    assigns =
      assigns
      |> assign(:model_entries, composer_model_entries(assigns.provider))
      |> assign(:composer_selected_model, selected_model)
      |> assign(
        :model_adjustment_notice,
        model_adjustment_notice(assigns.provider, assigns.selected_model, selected_model)
      )

    ~H"""
    <form
      phx-submit="send_message"
      phx-change="validate_upload"
      class="rounded-box border border-[var(--border-subtle)] focus-within:border-primary/40 bg-[var(--surface-composer)] shadow-sm outline-none transition-colors"
      id="message-form"
      data-slash-items={Jason.encode!(@slash_items)}
      data-session-flags={Jason.encode!(serialize_cli_opts(@session_cli_opts))}
      phx-hook="DmComposer"
    >
      <%!-- Upload previews --%>
      <%= if @uploads.files.entries != [] do %>
        <div class="px-4 pt-3 flex flex-wrap gap-2" id="upload-preview-list">
          <%= for entry <- @uploads.files.entries do %>
            <div class="flex items-center gap-2 rounded-box bg-base-content/[0.04] px-3 py-1.5 text-mini">
              <.icon name="hero-paper-clip" class="size-3.5 text-base-content/40" />
              <span class="text-base-content/70">{entry.client_name}</span>
              <span class="text-base-content/30">{FileHelpers.format_size(entry.client_size)}</span>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                class="flex items-center justify-center text-base-content/30 hover:text-error transition-colors min-w-[44px] min-h-[44px]"
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
              @processing -> "Queue a message..."
              @display_name -> "Reply to #{@display_name}..."
              true -> "Reply..."
            end
          }
          class="w-full bg-transparent border-0 outline-none focus:ring-0 text-message resize-none min-h-[56px] max-h-40 overflow-y-auto placeholder:text-base-content/30 p-0 leading-relaxed"
          autocomplete="off"
          phx-hook="CommandHistory"
          id="message-input"
          data-session-uuid={@session_uuid}
          data-vim-composer
        ></textarea>
      </div>

      <%!-- Format bar | hidden until Aa is clicked --%>
      <div id="format-bar" class="hidden px-3 pb-1 flex items-center gap-0.5">
        <button
          type="button"
          data-fmt="bold"
          title="Bold"
          class="flex items-center justify-center w-7 h-7 rounded text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 transition-colors"
        >
          <span class="font-bold text-message leading-none">B</span>
        </button>
        <button
          type="button"
          data-fmt="italic"
          title="Italic"
          class="flex items-center justify-center w-7 h-7 rounded text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 transition-colors"
        >
          <span class="italic text-message leading-none">I</span>
        </button>
        <button
          type="button"
          data-fmt="strike"
          title="Strikethrough"
          class="flex items-center justify-center w-7 h-7 rounded text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 transition-colors"
        >
          <span class="line-through text-message leading-none">S</span>
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
            class="flex items-center justify-center w-11 h-11 sm:w-8 sm:h-8 rounded-box cursor-pointer text-base-content/30 hover:text-base-content/60 hover:bg-base-content/5 transition-colors"
          >
            <.icon name="hero-plus" class="size-5" />
          </label>
          <button
            type="button"
            id="formatter-toggle"
            title="Format text"
            class="flex items-center justify-center w-11 h-11 sm:w-8 sm:h-8 rounded-box text-base-content/30 hover:text-base-content/60 hover:bg-base-content/5 transition-colors"
          >
            <span class="text-mini font-semibold tracking-normal select-none">Aa</span>
          </button>
          <%!-- Plan mode toggle --%>
          <button
            type="button"
            phx-click="toggle_plan_mode"
            title={
              if Keyword.get(@session_cli_opts, :permission_mode) == "plan",
                do: "Plan mode on | click to disable",
                else: "Enable plan mode (agent will propose changes before acting)"
            }
            class={[
              "flex items-center justify-center w-11 h-11 sm:w-8 sm:h-8 rounded-box transition-colors",
              if(Keyword.get(@session_cli_opts, :permission_mode) == "plan",
                do: "text-warning bg-warning/10 hover:bg-warning/15",
                else: "text-base-content/30 hover:text-base-content/60 hover:bg-base-content/5"
              )
            ]}
          >
            <.icon name="hero-book-open" class="size-4" />
          </button>
          <.live_file_input upload={@uploads.files} class="hidden" />
          <%!-- Active CLI flags indicator | surfaces session-level flags set via
               slash command (/sandbox, /add-dir, /mcp, /max-turns, etc.) that
               have no other dedicated toolbar control. --%>
          <.flags_badge session_cli_opts={@session_cli_opts} />
          <%!-- Budget cap input --%>
          <div class="flex items-center gap-0.5 text-mini text-base-content/40">
            <span class="font-mono">$</span>
            <input
              type="number"
              min="0"
              step="0.01"
              placeholder=""
              value={@max_budget_usd}
              phx-blur="set_max_budget"
              class="w-16 bg-transparent border-0 outline-none focus:ring-0 text-mini placeholder:text-base-content/20 font-mono p-0 [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
            />
          </div>
          <%!-- ReasoningPill: [🧠 Thinking] | [👁] | [effort ▾] --%>
          <.reasoning_pill
            provider={@provider}
            thinking_enabled={@thinking_enabled}
            show_thinking_blocks={@show_thinking_blocks}
            selected_effort={@selected_effort}
            active_overlay={@active_overlay}
          />
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
          <div class="flex flex-col items-end gap-1">
            <div
              :if={@model_adjustment_notice}
              id="composer-model-adjustment-notice"
              class="flex max-w-[18rem] items-center gap-1.5 rounded-box border border-warning/20 bg-warning/10 px-2 py-1 text-micro font-mono text-warning/80"
            >
              <.icon name="hero-exclamation-circle-mini" class="size-3 shrink-0" />
              <span class="truncate">{@model_adjustment_notice}</span>
            </div>
            <.model_selector
              id="composer-model-selector"
              entries={@model_entries}
              selected_provider={@provider}
              selected_model={@composer_selected_model}
              allow_provider_switch?={false}
              event="select_model"
              disabled?={@processing}
              placement={:up}
            />
          </div>

          <%!-- Send / Stop --%>
          <div class="flex items-center gap-1.5">
            <%= if @processing do %>
              <button
                type="submit"
                class="flex items-center justify-center gap-1.5 px-3 h-7 min-h-[44px] rounded-box bg-base-content/[0.06] text-base-content/40 hover:bg-base-content/10 transition-colors text-mini font-semibold"
                id="dm-queue-button"
                title="Add to queue"
              >
                Queue <kbd class="text-micro font-mono opacity-55 leading-none">↵</kbd>
              </button>
              <button
                type="button"
                phx-click="kill_session"
                class="flex items-center justify-center gap-1.5 px-3 h-7 min-h-[44px] rounded-box bg-error/80 text-error-content hover:bg-error transition-colors text-mini font-semibold"
                id="dm-stop-button"
              >
                <.icon name="hero-stop-solid" class="size-3.5" /> Stop
              </button>
            <% else %>
              <button
                type="submit"
                class="flex items-center justify-center gap-1.5 px-3 h-7 min-h-[44px] rounded-box bg-primary/80 text-primary-content hover:bg-primary transition-colors text-mini font-semibold"
                id="dm-send-button"
              >
                Send <kbd class="text-micro font-mono opacity-55 leading-none">↵</kbd>
              </button>
            <% end %>
          </div>
        </div>
      </div>
    </form>
    """
  end

  defp composer_model_entries("codex") do
    "codex"
    |> ModelHelpers.entries_for_provider()
    |> Enum.reject(&(&1.slug == "gpt-5.2"))
  end

  defp composer_model_entries(provider), do: ModelHelpers.entries_for_provider(provider)

  defp composer_selected_model("codex", "gpt-5.2"), do: ModelHelpers.default_model_for("codex")
  defp composer_selected_model(_provider, selected_model), do: selected_model

  defp model_adjustment_notice("codex", "gpt-5.2", selected_model),
    do: "gpt-5.2 unavailable; using #{selected_model}"

  defp model_adjustment_notice(_provider, _requested_model, _selected_model), do: nil

  # ─── Active flags badge ─────────────────────────────────────────────────────
  # Shows a small flag icon + hover tooltip listing session-level CLI opts
  # (sandbox, add-dir, mcp, plugin, config, agents, max-turns, permissions)
  # that were set via slash command and have no dedicated toolbar control.
  # Model/effort/plan-mode are handled by their own pills and intentionally
  # excluded here (they never appear in session_cli_opts | see
  # SlashCommands.opt_key_to_slug/0).

  attr :session_cli_opts, :list, default: []

  defp flags_badge(assigns) do
    flags = serialize_cli_opts(assigns.session_cli_opts)
    assigns = assign(assigns, :flags, flags)

    ~H"""
    <div
      :if={@flags != []}
      class="flex items-center justify-center w-11 h-11 sm:w-8 sm:h-8 rounded-box text-primary/60 hover:bg-base-content/5 transition-colors cursor-default"
      title={Enum.map_join(@flags, "\n", &flag_display/1)}
    >
      <.icon name="hero-flag" class="size-4" />
    </div>
    """
  end

  defp flag_display(%{slug: slug, value: true}), do: "/#{slug}"
  defp flag_display(%{slug: slug, value: value}), do: "/#{slug} #{value}"

  # ─── ReasoningPill ───────────────────────────────────────────────────────────

  attr :provider, :string, required: true
  attr :thinking_enabled, :boolean, required: true
  attr :show_thinking_blocks, :boolean, required: true
  attr :selected_effort, :string, required: true
  attr :active_overlay, :any, required: true

  defp reasoning_pill(assigns) do
    # Classify provider for rendering decisions
    assigns =
      assign(assigns, :is_claude, assigns.provider not in ["codex", "pi"])

    ~H"""
    <div
      class={[
        "inline-flex items-center rounded-box border transition-colors",
        if(@thinking_enabled and @is_claude,
          do: "border-primary/30 bg-primary/[0.04]",
          else: "border-base-content/[0.10] bg-base-content/[0.03]"
        )
      ]}
      id="reasoning-pill"
    >
      <%!-- Segment 1: Thinking toggle (Claude only) --%>
      <%= if @is_claude do %>
        <button
          type="button"
          phx-click="toggle_thinking"
          title={
            if @thinking_enabled,
              do: "Thinking on | click to disable",
              else: "Enable extended thinking"
          }
          class={[
            "flex items-center gap-1.5 px-2.5 h-6 text-mini font-medium transition-colors rounded-l-lg",
            if(@thinking_enabled,
              do: "text-primary hover:text-primary/80",
              else: "text-base-content/40 hover:text-base-content/65"
            )
          ]}
        >
          <.icon name="hero-sparkles" class="size-3 flex-shrink-0" />
          <span>Think</span>
        </button>
        <div class="w-px h-4 bg-base-content/[0.10] flex-shrink-0" />
      <% else %>
        <%!-- Codex / Pi: always-on indicator, non-interactive --%>
        <span class="flex items-center gap-1.5 px-2.5 h-6 text-mini font-medium text-base-content/40 select-none rounded-l-lg">
          <.icon name="hero-sparkles" class="size-3 flex-shrink-0" />
          <span>Think</span>
        </span>
        <div class="w-px h-4 bg-base-content/[0.10] flex-shrink-0" />
      <% end %>

      <%!-- Segment 2: Show/hide thinking blocks --%>
      <button
        type="button"
        phx-click="toggle_show_thinking"
        title={
          if @show_thinking_blocks,
            do: "Thinking blocks visible | click to hide",
            else: "Show thinking blocks in chat"
        }
        class={[
          "flex items-center justify-center w-6 h-6 transition-colors",
          if(@show_thinking_blocks,
            do: "text-base-content/70 hover:text-base-content/90",
            else: "text-base-content/30 hover:text-base-content/55"
          )
        ]}
      >
        <%= if @show_thinking_blocks do %>
          <.icon name="hero-eye" class="size-3" />
        <% else %>
          <.icon name="hero-eye-slash" class="size-3" />
        <% end %>
      </button>
      <div class="w-px h-4 bg-base-content/[0.10] flex-shrink-0" />

      <%!-- Segment 3: Effort level picker --%>
      <%!-- phx-click must be on the .dropdown div (not the inner button) so that --%>
      <%!-- focus stays on the child after the LiveView re-render, keeping the    --%>
      <%!-- DaisyUI :focus-within selector true and the menu visible.             --%>
      <div
        class="dropdown dropdown-top"
        phx-click="toggle_effort_menu"
        id="reasoning-pill-effort-dropdown"
      >
        <button
          type="button"
          tabindex="0"
          title="Reasoning effort"
          class="flex items-center gap-1 px-2 h-6 text-mini font-medium text-base-content/50 hover:text-base-content/75 transition-colors rounded-r-lg"
          id="reasoning-pill-effort-button"
        >
          <span>{DmHelpers.effort_display_name(@selected_effort)}</span>
          <.icon name="hero-chevron-down-mini" class="size-3 flex-shrink-0" />
        </button>
        <%= if @active_overlay == :effort_menu do %>
          <ul
            tabindex="0"
            class="dropdown-content menu z-[1] w-52 rounded-box border border-base-content/8 bg-base-100 p-1.5 shadow-lg mb-1"
            id="reasoning-pill-effort-menu"
          >
            <li class="menu-title text-mini px-3 pt-1 pb-0.5 text-base-content/40">
              Effort Level
            </li>
            <%= for {label, value, desc, color} <- effort_levels(@is_claude) do %>
              <li>
                <a
                  phx-click="select_effort"
                  phx-value-effort={value}
                  class={[
                    "flex items-center gap-3 rounded-box px-3 py-2 hover:bg-base-content/[0.04]",
                    @selected_effort == value && "bg-base-content/[0.06]"
                  ]}
                >
                  <div>
                    <div class={"text-message font-semibold " <> color}>{label}</div>
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
    </div>
    """
  end

  # Effort level menu items per provider variant.
  defp effort_levels(true = _is_claude) do
    [
      {"Auto", "auto", "Let Claude decide", "text-base-content/70"},
      {"Low", "low", "Faster, cheaper", "text-success"},
      {"Medium", "medium", "Balanced (default)", "text-info"},
      {"High", "high", "Deeper reasoning", "text-warning"},
      {"XHigh", "xhigh", "Extended reasoning", "text-warning"},
      {"Max", "max", "Maximum effort", "text-error"}
    ]
  end

  defp effort_levels(false) do
    [
      {"Low", "low", "Faster, cheaper", "text-success"},
      {"Medium", "medium", "Balanced (default)", "text-info"},
      {"High", "high", "Deeper reasoning", "text-warning"},
      {"XHigh", "xhigh", "Extended reasoning", "text-warning"}
    ]
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
    {bar_color, label_color, progress_color} =
      cond do
        pct < 35 -> {"bg-success/70", "text-success/70", "progress-success"}
        pct < 65 -> {"bg-warning/70", "text-warning/70", "progress-warning"}
        true -> {"bg-error/70", "text-error/70", "progress-error"}
      end

    assigns =
      assigns
      |> Map.put(:ratio, ratio)
      |> Map.put(:pct, pct)
      |> Map.put(:system_share, system_share)
      |> Map.put(:files_share, files_share)
      |> Map.put(:conv_share, conv_share)
      |> Map.put(:bar_color, bar_color)
      |> Map.put(:label_color, label_color)
      |> Map.put(:progress_color, progress_color)

    ~H"""
    <div class="relative dropdown dropdown-top">
      <%!-- Trigger: progress bar --%>
      <button
        type="button"
        phx-click="toggle_context_meter"
        class={"cursor-pointer flex items-center " <> @label_color}
        title={"#{format_number(@context_used)} / #{format_number(@context_window)} tokens | click for details"}
        aria-label="Context window usage"
      >
        <progress
          class={"progress h-1.5 w-20 " <> @progress_color}
          value={round(@pct)}
          max="100"
        />
      </button>

      <%!-- Popover --%>
      <%= if @active_overlay == :context_meter do %>
        <div
          class="dropdown-content z-50 mb-2 w-64 rounded-box border border-base-content/10 bg-base-100 shadow-xl p-4"
          role="dialog"
          aria-label="Context window details"
        >
          <%!-- Header --%>
          <div class="flex items-center justify-between mb-3">
            <span class="text-mini font-semibold uppercase tracking-normal text-base-content/40">
              Context
            </span>
            <span class={"text-mini font-mono font-semibold " <> @label_color}>
              {round(@pct)}% used
            </span>
          </div>

          <%!-- Progress bar --%>
          <progress
            class={"progress w-full h-1.5 mb-2 " <> @progress_color}
            value={round(@pct)}
            max="100"
          />

          <%!-- Legend --%>
          <div class="space-y-1 mb-3">
            <div class="flex items-center justify-between text-mini text-base-content/50">
              <span class="flex items-center gap-1.5">
                <span class="w-2 h-2 rounded-sm bg-base-content/30 flex-shrink-0" /> System + tools
              </span>
              <span class="font-mono">{format_number(round(@system_share * @context_window))}</span>
            </div>
            <div class="flex items-center justify-between text-mini text-base-content/50">
              <span class="flex items-center gap-1.5">
                <span class={"w-2 h-2 rounded-sm flex-shrink-0 " <> @bar_color} /> Conversation
              </span>
              <span class="font-mono">{format_number(round(@conv_share * @context_window))}</span>
            </div>
            <div class="flex items-center justify-between text-mini text-base-content/50">
              <span class="flex items-center gap-1.5">
                <span class="w-2 h-2 rounded-sm bg-info/50 flex-shrink-0" /> Latest files
              </span>
              <span class="font-mono">{format_number(round(@files_share * @context_window))}</span>
            </div>
          </div>

          <%!-- Divider --%>
          <div class="border-t border-base-content/[0.06] my-3" />

          <%!-- Token count + cost --%>
          <div class="flex items-center justify-between mb-3">
            <span class="text-mini text-base-content/40 font-mono">
              {format_number(@context_used)} / {format_number(@context_window)}
            </span>
            <%= if @total_cost > 0 do %>
              <span class="text-mini font-mono text-base-content/40">
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
              class="flex-1 rounded-box bg-base-content/[0.05] hover:bg-base-content/[0.09] border border-base-content/[0.08] text-mini font-medium text-base-content/60 py-1.5 transition-colors"
            >
              Compact
            </button>
            <button
              type="button"
              phx-click="send_slash_command"
              phx-value-command="/clear"
              class="flex-1 rounded-box bg-base-content/[0.05] hover:bg-base-content/[0.09] border border-base-content/[0.08] text-mini font-medium text-base-content/60 py-1.5 transition-colors"
            >
              Clear
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

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
