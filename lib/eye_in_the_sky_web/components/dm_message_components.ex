defmodule EyeInTheSkyWeb.Components.DmMessageComponents do
  @moduledoc """
  Message rendering components for the DM page.

  Covers the full message display hierarchy:
    message_item -> message_body -> tool_widget -> tool_widget_body
                 -> message_metrics
                 -> message_attachments

  Also exports stream_provider_avatar for the live-stream bubble.

  Imported by DmPage so all <.component_name ...> call-sites are unchanged.
  """

  use EyeInTheSkyWeb, :html

  import EyeInTheSkyWeb.Components.DmHelpers

  # ---------------------------------------------------------------------------
  # message_item
  # ---------------------------------------------------------------------------

  attr :message, :map, required: true

  def message_item(assigns) do
    is_user = assigns.message.sender_role == "user"
    is_dm = dm_message?(assigns.message)
    assigns = assign(assigns, :is_user, is_user) |> assign(:is_dm, is_dm)

    ~H"""
    <div
      class={[
        "py-3 px-2 -mx-2 rounded-lg opacity-0",
        @is_dm && "border-l-2 border-primary/30 pl-3 bg-primary/[0.03]"
      ]}
      id={"dm-message-#{@message.id}"}
      phx-mounted={
        JS.transition(
          {"transition-all ease-out duration-200", "opacity-0 translate-y-1",
           "opacity-100 translate-y-0"}
        )
      }
    >
      <div class="flex items-start gap-2.5">
        <%!-- Sender icon --%>
        <%= if @is_user do %>
          <div class="w-4 h-4 rounded-full mt-1 flex-shrink-0 bg-success/20 flex items-center justify-center">
            <div class="w-1.5 h-1.5 rounded-full bg-success" />
          </div>
        <% else %>
          <img
            src={provider_icon(@message.provider)}
            class={"w-4 h-4 mt-1 flex-shrink-0 #{provider_icon_class(@message.provider)}"}
            alt={@message.provider || "Agent"}
            width="16"
            height="16"
            loading="lazy"
          />
        <% end %>

        <div class="min-w-0 flex-1">
          <div class="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
            <span class={[
              "text-[13px] font-semibold",
              !@is_user && "text-primary/80",
              @is_user && "text-base-content/70"
            ]}>
              {message_sender_name(@message)}
            </span>
            <%!-- DM badge --%>
            <span
              :if={@is_dm}
              class="inline-flex items-center gap-1 text-xs font-mono px-1.5 py-0.5 rounded bg-base-content/[0.05] text-base-content/40 uppercase tracking-wide"
            >
              <.icon name="hero-envelope-mini" class="w-2.5 h-2.5" /> dm
            </span>
            <span
              :if={!@is_user && message_model(@message)}
              class="text-[11px] font-mono px-1.5 py-0.5 rounded bg-base-content/[0.05] text-base-content/35"
            >
              {message_model(@message)}
            </span>
            <span
              :if={!@is_user && message_cost(@message)}
              class="text-[11px] font-mono text-base-content/30"
            >
              ${:erlang.float_to_binary(message_cost(@message) * 1.0, decimals: 4)}
            </span>
            <time
              id={"msg-time-#{@message.id}"}
              class="text-[11px] text-base-content/25"
              data-utc={to_utc_string(@message.inserted_at)}
              phx-hook="LocalTime"
            >
            </time>
          </div>

          <.message_body message={@message} />

          <.message_metrics :if={show_message_metrics?(@message)} message={@message} />
          <.message_attachments attachments={@message.attachments || []} />
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # message_metrics
  # ---------------------------------------------------------------------------

  attr :message, :map, required: true

  def message_metrics(assigns) do
    ~H"""
    <div class="mt-2 flex flex-wrap gap-1.5">
      <%= if @message.metadata["total_cost_usd"] do %>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40"
          title="Total cost"
        >
          <.icon name="hero-currency-dollar-mini" class="w-3 h-3" />
          {:erlang.float_to_binary(@message.metadata["total_cost_usd"] * 1.0, decimals: 4)}
        </span>
      <% end %>

      <%= if @message.metadata["usage"] && @message.metadata["usage"]["input_tokens"] do %>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40"
          title="Input tokens"
        >
          {@message.metadata["usage"]["input_tokens"]} in
        </span>
      <% end %>

      <%= if @message.metadata["usage"] && @message.metadata["usage"]["output_tokens"] do %>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40"
          title="Output tokens"
        >
          {@message.metadata["usage"]["output_tokens"]} out
        </span>
      <% end %>

      <%= if @message.metadata["duration_ms"] do %>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40"
          title="Duration"
        >
          <.icon name="hero-clock-mini" class="w-3 h-3" />
          {:erlang.float_to_binary(@message.metadata["duration_ms"] * 1.0 / 1000, decimals: 1)}s
        </span>
      <% end %>

      <%= if @message.metadata["num_turns"] do %>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40"
          title="Number of turns"
        >
          {@message.metadata["num_turns"]} turns
        </span>
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # message_attachments
  # ---------------------------------------------------------------------------

  attr :attachments, :list, default: []

  def message_attachments(assigns) do
    ~H"""
    <%= if @attachments != [] do %>
      <div class="mt-2 space-y-1">
        <%= for attachment <- @attachments do %>
          <div class="flex items-center gap-2 rounded-md bg-base-content/[0.04] px-2.5 py-1.5 text-[11px] font-mono">
            <.icon name="hero-paper-clip" class="h-3 w-3 text-base-content/30" />
            <span class="text-base-content/60">{attachment.original_filename}</span>
            <span class="ml-auto text-base-content/25">{attachment.storage_path}</span>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # message_body
  # ---------------------------------------------------------------------------

  attr :message, :map, required: true

  def message_body(assigns) do
    body =
      if dm_message?(assigns.message),
        do: strip_dm_prefix(assigns.message.body),
        else: assigns.message.body

    segments = parse_body_segments(body)
    thinking = get_in(assigns.message.metadata || %{}, ["thinking"])
    stream_type = get_in(assigns.message.metadata || %{}, ["stream_type"])

    assigns =
      assigns
      |> assign(:segments, segments)
      |> assign(:thinking, thinking)
      |> assign(:stream_type, stream_type)

    ~H"""
    <div class="mt-1 space-y-1.5">
      <details
        :if={@thinking && @thinking != ""}
        class="group rounded border-l-2 border-primary/50 bg-zinc-950/50 overflow-hidden"
      >
        <summary class="flex items-center gap-2 px-2.5 py-1.5 cursor-pointer select-none list-none hover:bg-base-content/[0.04] transition-colors">
          <.icon name="hero-sparkles" class="w-3.5 h-3.5 flex-shrink-0 text-primary/60" />
          <span class="text-[11px] font-mono font-semibold text-primary/60 uppercase tracking-wide">
            Thinking
          </span>
          <.icon
            name="hero-chevron-right"
            class="w-3 h-3 text-base-content/20 ml-auto flex-shrink-0 transition-transform group-open:rotate-90"
          />
        </summary>
        <div class="px-2.5 pb-2 pt-1 border-t border-primary/10">
          <pre class="font-mono text-xs text-base-content/40 whitespace-pre-wrap break-words leading-relaxed">{@thinking}</pre>
        </div>
      </details>
      <%= if @stream_type == "tool_result" do %>
        <.tool_result_body body={@message.body} />
      <% else %>
        <%= for {segment, idx} <- Enum.with_index(@segments) do %>
          <%= case segment do %>
            <% {:tool_call, name, rest} -> %>
              <.tool_widget name={name} rest={rest} />
            <% {:text, text} when text != "" -> %>
              <div
                id={"msg-body-#{@message.id}-#{idx}"}
                class="dm-markdown text-sm leading-relaxed text-base-content/85"
                phx-hook="MarkdownMessage"
                data-raw-body={text}
              >
              </div>
            <% _ -> %>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # tool_result_body
  # ---------------------------------------------------------------------------

  attr :body, :string, default: ""

  def tool_result_body(assigns) do
    ~H"""
    <details
      open
      class="group rounded-md border border-base-content/8 bg-base-content/[0.025] overflow-hidden"
    >
      <summary class="flex items-center gap-2 px-2.5 py-1.5 cursor-pointer select-none list-none hover:bg-base-content/[0.04] transition-colors">
        <.icon name="hero-code-bracket" class="w-3.5 h-3.5 flex-shrink-0 text-base-content/30" />
        <span class="text-[11px] font-mono font-semibold text-base-content/40 uppercase tracking-wide flex-shrink-0">
          Output
        </span>
        <button
          class="tool-copy-btn ml-auto mr-1 shrink-0"
          data-copy-btn
          data-copy-text={@body}
          title="Copy output"
        >
          <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" />
        </button>
        <.icon
          name="hero-chevron-right"
          class="w-3 h-3 text-base-content/20 shrink-0 transition-transform group-open:rotate-90"
        />
      </summary>
      <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5">
        <pre class="font-mono text-xs text-base-content/55 whitespace-pre-wrap break-all leading-relaxed max-h-64 overflow-y-auto">{@body}</pre>
      </div>
    </details>
    """
  end

  # ---------------------------------------------------------------------------
  # tool_widget
  # ---------------------------------------------------------------------------

  attr :name, :string, required: true
  attr :rest, :string, required: true

  def tool_widget(assigns) do
    {icon, label, detail} = tool_widget_meta(assigns.name, assigns.rest)

    input =
      case Jason.decode(assigns.rest) do
        {:ok, map} when is_map(map) -> map
        _ -> nil
      end

    wrap_detail = label == "i-speak"

    assigns =
      assigns
      |> assign(:icon, icon)
      |> assign(:label, label)
      |> assign(:detail, detail)
      |> assign(:input, input)
      |> assign(:wrap_detail, wrap_detail)

    ~H"""
    <details class="group rounded-md border border-base-content/8 bg-base-content/[0.025] overflow-hidden">
      <summary class="flex items-center gap-2 px-2.5 py-1.5 cursor-pointer select-none list-none hover:bg-base-content/[0.04] transition-colors">
        <.icon name={@icon} class="w-3.5 h-3.5 flex-shrink-0 text-base-content/35" />
        <span class="text-[11px] font-mono font-semibold text-base-content/45 uppercase tracking-wide flex-shrink-0">
          {@label}
        </span>
        <span
          :if={@detail != "" && !@wrap_detail}
          class="text-[11px] font-mono text-base-content/35 truncate flex-1 min-w-0"
        >
          {@detail}
        </span>
        <button
          class="tool-copy-btn ml-auto mr-1 shrink-0"
          data-copy-btn
          data-copy-text={@rest}
          title="Copy input"
        >
          <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" />
        </button>
        <.icon
          name="hero-chevron-right"
          class="w-3 h-3 text-base-content/20 shrink-0 transition-transform group-open:rotate-90"
        />
      </summary>
      <.tool_widget_body name={@name} rest={@rest} detail={@detail} input={@input} />
    </details>
    """
  end

  # ---------------------------------------------------------------------------
  # tool_widget_body
  # ---------------------------------------------------------------------------

  attr :name, :string, required: true
  attr :rest, :string, required: true
  attr :detail, :string, required: true
  attr :input, :any, default: nil

  def tool_widget_body(assigns) do
    assigns = assign(assigns, :body_type, classify_body_type(assigns))

    ~H"""
    <%= case @body_type do %>
      <% :bash -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5">
          <pre class="bg-base-200 rounded px-2 py-1.5 font-mono text-xs text-base-content/70 whitespace-pre-wrap break-all leading-relaxed">{(@input && @input["command"]) || @detail}</pre>
        </div>
      <% :edit -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5 space-y-1.5">
          <div class="font-mono text-xs text-base-content/40 pb-0.5">{@input["file_path"]}</div>
          <pre class="bg-red-950/30 text-red-400/70 rounded px-2 py-1 font-mono text-xs whitespace-pre-wrap break-all leading-relaxed max-h-32 overflow-y-auto">{String.slice(@input["old_string"] || "", 0..500)}</pre>
          <pre class="bg-green-950/30 text-green-400/70 rounded px-2 py-1 font-mono text-xs whitespace-pre-wrap break-all leading-relaxed max-h-32 overflow-y-auto">{String.slice(@input["new_string"] || "", 0..500)}</pre>
        </div>
      <% :write -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5 space-y-1">
          <div class="font-mono text-xs text-base-content/40 pb-0.5">{@input["file_path"]}</div>
          <pre class="bg-base-200 rounded px-2 py-1.5 font-mono text-xs text-base-content/55 whitespace-pre-wrap break-all leading-relaxed max-h-48 overflow-y-auto">{String.slice(@input["content"] || "", 0..500)}{if String.length(@input["content"] || "") > 500, do: "\n…", else: ""}</pre>
        </div>
      <% :speak -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5">
          <pre class="bg-base-200 rounded px-2 py-1.5 text-[11px] text-base-content/70 whitespace-pre-wrap break-all leading-relaxed">{@detail}</pre>
        </div>
      <% :json -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5">
          <pre class="font-mono text-xs text-base-content/40 whitespace-pre-wrap break-all leading-relaxed max-h-40 overflow-y-auto">{Jason.encode!(@input, pretty: true)}</pre>
        </div>
      <% :text -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5">
          <pre class="font-mono text-xs text-base-content/45 whitespace-pre-wrap break-all leading-relaxed">{@rest}</pre>
        </div>
      <% :none -> %>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # classify_body_type helpers
  # ---------------------------------------------------------------------------

  defp classify_body_type(assigns) do
    cond do
      bash_body?(assigns) -> :bash
      edit_body?(assigns) -> :edit
      write_body?(assigns) -> :write
      speak_body?(assigns) -> :speak
      json_body?(assigns) -> :json
      text_body?(assigns) -> :text
      true -> :none
    end
  end

  defp bash_body?(assigns), do: assigns.name == "Bash" and assigns.rest != ""

  defp edit_body?(assigns) do
    assigns.name == "Edit" and is_map(assigns.input) and
      Map.has_key?(assigns.input, "old_string")
  end

  defp write_body?(assigns) do
    assigns.name == "Write" and is_map(assigns.input) and
      Map.has_key?(assigns.input, "content")
  end

  defp speak_body?(assigns),
    do: String.ends_with?(assigns.name, "i-speak") and assigns.detail != ""

  defp json_body?(assigns) do
    is_map(assigns.input) and map_size(assigns.input) > 0 and
      assigns.name not in ["Read", "Glob", "Grep", "WebSearch", "Task"]
  end

  defp text_body?(assigns), do: assigns.rest != "" and assigns.rest != assigns.detail

  # ---------------------------------------------------------------------------
  # stream_provider_avatar
  # ---------------------------------------------------------------------------

  attr :session, :map, default: nil

  def stream_provider_avatar(assigns) do
    provider = if assigns.session, do: assigns.session.provider, else: "claude"
    assigns = assign(assigns, :provider, provider)

    ~H"""
    <%= if @provider == "codex" do %>
      <img
        src="/images/openai.svg"
        class="w-4 h-4 mt-1 flex-shrink-0 animate-pulse"
        alt="Codex"
        width="16"
        height="16"
        loading="lazy"
      />
    <% else %>
      <img
        src="/images/claude.svg"
        class="w-4 h-4 mt-1 flex-shrink-0 animate-pulse"
        alt="Claude"
        width="16"
        height="16"
        loading="lazy"
      />
    <% end %>
    """
  end
end
