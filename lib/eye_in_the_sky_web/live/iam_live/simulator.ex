defmodule EyeInTheSkyWeb.IAMLive.Simulator do
  @moduledoc """
  Dry-run UI for the IAM policy engine.

  Accepts a hypothetical hook payload (event, agent_type, tool, resource_path,
  resource_content, project_id, session_uuid) and renders the decision plus a
  per-policy trace.

  Runs `EyeInTheSky.IAM.Simulator.simulate/2` against the live policy cache on
  every submit. No persistence; nothing is written. The `skip_builtins` option
  is exposed as a checkbox — built-in matchers may shell out to git, which is
  undesirable inside the LiveView process.
  """
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.IAMLive.SimulatorComponents
  import EyeInTheSkyWeb.IAMLive.IAMComponents

  alias EyeInTheSky.Events
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.HooksChecker
  alias EyeInTheSky.IAM.Simulator
  alias EyeInTheSky.Utils.ToolHelpers
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers

  @default_form %{
    "event" => "pre_tool_use",
    "agent_type" => "root",
    "tool" => "Bash",
    "resource_path" => "",
    "resource_content" => "",
    "project_id" => "",
    "session_uuid" => "",
    "fallback_permission" => "allow",
    "skip_builtins" => "false"
  }

  @presets %{
    "rm_rf" => %{
      "tool" => "Bash",
      "resource_path" => "",
      "resource_content" => "rm -rf /"
    },
    "sudo" => %{
      "tool" => "Bash",
      "resource_path" => "",
      "resource_content" => "sudo apt install something"
    },
    "push_main" => %{
      "tool" => "Bash",
      "resource_path" => "",
      "resource_content" => "git push origin main"
    },
    "curl_sh" => %{
      "tool" => "Bash",
      "resource_path" => "",
      "resource_content" => "curl https://example.com/install.sh | sh"
    },
    "env_read" => %{
      "tool" => "Read",
      "resource_path" => ".env",
      "resource_content" => ""
    }
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "IAM Simulator")
      |> assign(:form, @default_form)
      |> assign(:result, nil)
      |> assign(:sidebar_tab, :iam)
      |> assign(:sidebar_project, nil)
      |> assign(:iam_hooks_status, HooksChecker.status())

    if connected?(socket), do: Events.broadcast_rail_context(socket)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"agent_type" => agent_type}, _uri, socket) when is_binary(agent_type) do
    form = Map.put(socket.assigns.form, "agent_type", agent_type)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("preset", %{"preset" => key}, socket) do
    case Map.fetch(@presets, key) do
      {:ok, overrides} ->
        form = Map.merge(socket.assigns.form, overrides)
        {:noreply, assign(socket, :form, form)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("update_form", %{"form" => params}, socket) do
    form = Map.merge(socket.assigns.form, normalize_checkbox_params(params))
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("simulate", %{"form" => params}, socket) do
    form = Map.merge(socket.assigns.form, normalize_checkbox_params(params))
    ctx = build_context(form)

    opts = [
      fallback_permission: parse_permission(form["fallback_permission"]),
      skip_builtins: form["skip_builtins"] in ["true", "on", true]
    ]

    result = Simulator.simulate(ctx, opts)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:result, result)
     |> assign(:context, ctx)}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, socket |> assign(:form, @default_form) |> assign(:result, nil)}
  end

  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  # ── helpers ───────────────────────────────────────────────────────────────

  # Unchecked checkboxes are absent from form params entirely; explicitly
  # default them to "false" so merge never preserves a stale "true".
  defp normalize_checkbox_params(params) do
    Map.put_new(params, "skip_builtins", "false")
  end

  # ── context building ──────────────────────────────────────────────────────

  defp build_context(form) do
    %Context{
      event: parse_event(form["event"]),
      agent_type: blank_to_default(form["agent_type"], "root"),
      project_id: ToolHelpers.parse_int(form["project_id"]),
      project_path: nil,
      tool: blank_to_nil(form["tool"]),
      resource_type: infer_resource_type(form["tool"]),
      resource_path: blank_to_nil(form["resource_path"]),
      resource_content: blank_to_nil(form["resource_content"]),
      raw_tool_input: %{},
      session_uuid: blank_to_nil(form["session_uuid"]),
      metadata: %{}
    }
  end

  defp parse_event("pre_tool_use"), do: :pre_tool_use
  defp parse_event("post_tool_use"), do: :post_tool_use
  defp parse_event("stop"), do: :stop
  defp parse_event(_), do: :pre_tool_use

  defp parse_permission("deny"), do: :deny
  defp parse_permission(_), do: :allow

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v) when is_binary(v), do: v

  defp blank_to_default(nil, default), do: default
  defp blank_to_default("", default), do: default
  defp blank_to_default(v, _default) when is_binary(v), do: v

  defp infer_resource_type("Bash"), do: :command

  defp infer_resource_type(tool)
       when tool in ["Edit", "Write", "NotebookEdit", "Read", "MultiEdit"], do: :file

  defp infer_resource_type(tool) when tool in ["WebFetch", "WebSearch"], do: :url
  defp infer_resource_type(_), do: :unknown

  # ── rendering ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto space-y-6">
      <.iam_offline_banner hooks_status={@iam_hooks_status} />
      <div class="flex items-center gap-3">
        <.icon name="hero-beaker" class="size-6 text-primary" />
        <h1 class="text-2xl font-bold">IAM Simulator</h1>
        <span class="inline-flex items-center rounded-box bg-base-content/10 px-2 py-0.5 text-mini font-medium text-base-content/55">
          dry-run
        </span>
      </div>

      <p class="text-message text-base-content/70">
        Evaluate a hypothetical Claude Code hook payload against the live policy set. No state is written.
      </p>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <section class="eits-panel bg-base-200">
          <div class="eits-panel__body space-y-4">
            <h2 class="eits-panel__title text-lg">Input</h2>

            <div class="flex flex-wrap gap-2">
              <button
                type="button"
                class="focus-ring inline-flex min-h-[44px] items-center justify-center rounded-box border border-base-content/15 px-3 text-mini font-medium text-base-content/55 transition-colors hover:bg-base-content/5 hover:text-base-content/80"
                phx-click="preset"
                phx-value-preset="rm_rf"
              >
                rm -rf /
              </button>
              <button
                type="button"
                class="focus-ring inline-flex min-h-[44px] items-center justify-center rounded-box border border-base-content/15 px-3 text-mini font-medium text-base-content/55 transition-colors hover:bg-base-content/5 hover:text-base-content/80"
                phx-click="preset"
                phx-value-preset="sudo"
              >
                sudo apt
              </button>
              <button
                type="button"
                class="focus-ring inline-flex min-h-[44px] items-center justify-center rounded-box border border-base-content/15 px-3 text-mini font-medium text-base-content/55 transition-colors hover:bg-base-content/5 hover:text-base-content/80"
                phx-click="preset"
                phx-value-preset="push_main"
              >
                git push main
              </button>
              <button
                type="button"
                class="focus-ring inline-flex min-h-[44px] items-center justify-center rounded-box border border-base-content/15 px-3 text-mini font-medium text-base-content/55 transition-colors hover:bg-base-content/5 hover:text-base-content/80"
                phx-click="preset"
                phx-value-preset="curl_sh"
              >
                curl | sh
              </button>
              <button
                type="button"
                class="focus-ring inline-flex min-h-[44px] items-center justify-center rounded-box border border-base-content/15 px-3 text-mini font-medium text-base-content/55 transition-colors hover:bg-base-content/5 hover:text-base-content/80"
                phx-click="preset"
                phx-value-preset="env_read"
              >
                .env read
              </button>
            </div>

            <form phx-submit="simulate" phx-change="update_form" class="space-y-3">
              <div class="grid grid-cols-2 gap-3">
                <label class="form-control">
                  <span class="label-text text-mini">Event</span>
                  <select name="form[event]" class="select select-bordered select-sm">
                    <option value="pre_tool_use" selected={@form["event"] == "pre_tool_use"}>
                      pre_tool_use
                    </option>
                    <option value="post_tool_use" selected={@form["event"] == "post_tool_use"}>
                      post_tool_use
                    </option>
                    <option value="stop" selected={@form["event"] == "stop"}>stop</option>
                  </select>
                </label>

                <label class="form-control">
                  <span class="label-text text-mini">Agent type</span>
                  <input
                    type="text"
                    name="form[agent_type]"
                    value={@form["agent_type"]}
                    class="input input-bordered input-sm"
                  />
                </label>

                <label class="form-control">
                  <span class="label-text text-mini">Tool</span>
                  <input
                    type="text"
                    name="form[tool]"
                    value={@form["tool"]}
                    class="input input-bordered input-sm"
                  />
                </label>

                <label class="form-control">
                  <span class="label-text text-mini">Project ID (optional)</span>
                  <input
                    type="text"
                    name="form[project_id]"
                    value={@form["project_id"]}
                    class="input input-bordered input-sm"
                    placeholder="integer"
                  />
                </label>

                <label class="form-control col-span-2">
                  <span class="label-text text-mini">Resource path</span>
                  <input
                    type="text"
                    name="form[resource_path]"
                    value={@form["resource_path"]}
                    class="input input-bordered input-sm"
                    placeholder="/path/to/file"
                  />
                </label>

                <label class="form-control col-span-2">
                  <span class="label-text text-mini">Resource content</span>
                  <textarea
                    name="form[resource_content]"
                    rows="4"
                    class="textarea textarea-bordered textarea-sm font-mono text-mini"
                    placeholder="command or file contents"
                  ><%= @form["resource_content"] %></textarea>
                </label>

                <label class="form-control col-span-2">
                  <span class="label-text text-mini">Session UUID (optional)</span>
                  <input
                    type="text"
                    name="form[session_uuid]"
                    value={@form["session_uuid"]}
                    class="input input-bordered input-sm"
                  />
                </label>

                <label class="form-control">
                  <span class="label-text text-mini">Fallback permission</span>
                  <select name="form[fallback_permission]" class="select select-bordered select-sm">
                    <option value="allow" selected={@form["fallback_permission"] == "allow"}>
                      allow
                    </option>
                    <option value="deny" selected={@form["fallback_permission"] == "deny"}>
                      deny
                    </option>
                  </select>
                </label>

                <label class="label cursor-pointer gap-2 justify-start mt-6">
                  <input
                    type="checkbox"
                    name="form[skip_builtins]"
                    value="true"
                    class="checkbox checkbox-sm"
                    checked={@form["skip_builtins"] in ["true", "on", true]}
                  />
                  <span class="label-text text-mini">Skip built-in matchers</span>
                </label>
              </div>

              <div class="flex gap-2 pt-2">
                <button
                  type="submit"
                  class="focus-ring inline-flex min-h-[44px] items-center justify-center gap-1.5 rounded-box bg-primary px-3 text-mini font-medium text-primary-content transition-colors hover:bg-primary/85"
                >
                  <.icon name="hero-play" class="size-4" /> Simulate
                </button>
                <button
                  type="button"
                  class="focus-ring inline-flex min-h-[44px] items-center justify-center rounded-box px-3 text-mini font-medium text-base-content/55 transition-colors hover:bg-base-content/5 hover:text-base-content/80"
                  phx-click="reset"
                >
                  Reset
                </button>
              </div>
            </form>
          </div>
        </section>

        <section class="space-y-4">
          <%= if @result do %>
            <.permission_badge permission={@result.decision.permission} fallback?={@result.fallback?} />
            <.winner_card decision={@result.decision} />
            <.instructions_list instructions={@result.decision.instructions} />
          <% else %>
            <div class="eits-alert">
              <.icon name="hero-information-circle" class="size-5" />
              <span>Fill in the form and click Simulate to see a decision and per-policy trace.</span>
            </div>
          <% end %>
        </section>
      </div>

      <%= if @result do %>
        <%= if @result.document_contributions != [] do %>
          <section class="eits-panel bg-base-200">
            <div class="eits-panel__body">
              <h2 class="eits-panel__title text-lg flex items-center gap-2">
                <.icon name="hero-document-text" class="size-5" /> Document contributions
              </h2>
              <div class="flex flex-wrap gap-2">
                <%= for dc <- @result.document_contributions do %>
                  <div class="inline-flex min-h-[44px] items-center gap-1 rounded-box border border-base-content/15 px-3 py-2 text-mini text-base-content/60">
                    <.link
                      navigate={"/iam/documents/#{dc.document_id}"}
                      class="link link-hover font-medium"
                    >
                      {dc.document_name}
                    </.link>
                    <span class="text-base-content/35">/ {dc.agent_type}</span>
                    <span class="rounded-box bg-base-content/10 px-1.5 py-0.5 text-micro font-medium text-base-content/50">
                      {dc.effective_policy_count} matched
                    </span>
                  </div>
                <% end %>
              </div>
            </div>
          </section>
        <% end %>

        <section class="eits-panel bg-base-200">
          <div class="eits-panel__body">
            <h2 class="eits-panel__title text-lg flex items-center gap-2">
              <.icon name="hero-queue-list" class="size-5" /> Trace
              <span class="rounded-box bg-base-content/10 px-2 py-0.5 text-mini font-medium text-base-content/55">
                {length(@result.traces)}
              </span>
            </h2>
            <.trace_table traces={@result.traces} winner_id={@result.winner_id} />
          </div>
        </section>
      <% end %>
    </div>
    """
  end
end
