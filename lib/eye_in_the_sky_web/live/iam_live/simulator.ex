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
    {:ok,
     socket
     |> assign(:page_title, "IAM Simulator")
     |> assign(:form, @default_form)
     |> assign(:result, nil)
     |> assign(:sidebar_tab, :iam)
     |> assign(:sidebar_project, nil)
     |> assign(:iam_hooks_status, HooksChecker.status())}
  end

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
        <span class="badge badge-ghost">dry-run</span>
      </div>

      <p class="text-sm text-base-content/70">
        Evaluate a hypothetical Claude Code hook payload against the live policy set. No state is written.
      </p>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <section class="card bg-base-200">
          <div class="card-body space-y-4">
            <h2 class="card-title text-lg">Input</h2>

            <div class="flex flex-wrap gap-2">
              <button
                type="button"
                class="btn btn-xs btn-outline"
                phx-click="preset"
                phx-value-preset="rm_rf"
              >
                rm -rf /
              </button>
              <button
                type="button"
                class="btn btn-xs btn-outline"
                phx-click="preset"
                phx-value-preset="sudo"
              >
                sudo apt
              </button>
              <button
                type="button"
                class="btn btn-xs btn-outline"
                phx-click="preset"
                phx-value-preset="push_main"
              >
                git push main
              </button>
              <button
                type="button"
                class="btn btn-xs btn-outline"
                phx-click="preset"
                phx-value-preset="curl_sh"
              >
                curl | sh
              </button>
              <button
                type="button"
                class="btn btn-xs btn-outline"
                phx-click="preset"
                phx-value-preset="env_read"
              >
                .env read
              </button>
            </div>

            <form phx-submit="simulate" phx-change="update_form" class="space-y-3">
              <div class="grid grid-cols-2 gap-3">
                <label class="form-control">
                  <span class="label-text text-xs">Event</span>
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
                  <span class="label-text text-xs">Agent type</span>
                  <input
                    type="text"
                    name="form[agent_type]"
                    value={@form["agent_type"]}
                    class="input input-bordered input-sm"
                  />
                </label>

                <label class="form-control">
                  <span class="label-text text-xs">Tool</span>
                  <input
                    type="text"
                    name="form[tool]"
                    value={@form["tool"]}
                    class="input input-bordered input-sm"
                  />
                </label>

                <label class="form-control">
                  <span class="label-text text-xs">Project ID (optional)</span>
                  <input
                    type="text"
                    name="form[project_id]"
                    value={@form["project_id"]}
                    class="input input-bordered input-sm"
                    placeholder="integer"
                  />
                </label>

                <label class="form-control col-span-2">
                  <span class="label-text text-xs">Resource path</span>
                  <input
                    type="text"
                    name="form[resource_path]"
                    value={@form["resource_path"]}
                    class="input input-bordered input-sm"
                    placeholder="/path/to/file"
                  />
                </label>

                <label class="form-control col-span-2">
                  <span class="label-text text-xs">Resource content</span>
                  <textarea
                    name="form[resource_content]"
                    rows="4"
                    class="textarea textarea-bordered textarea-sm font-mono text-xs"
                    placeholder="command or file contents"
                  ><%= @form["resource_content"] %></textarea>
                </label>

                <label class="form-control col-span-2">
                  <span class="label-text text-xs">Session UUID (optional)</span>
                  <input
                    type="text"
                    name="form[session_uuid]"
                    value={@form["session_uuid"]}
                    class="input input-bordered input-sm"
                  />
                </label>

                <label class="form-control">
                  <span class="label-text text-xs">Fallback permission</span>
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
                  <span class="label-text text-xs">Skip built-in matchers</span>
                </label>
              </div>

              <div class="flex gap-2 pt-2">
                <button type="submit" class="btn btn-primary btn-sm">
                  <.icon name="hero-play" class="size-4" /> Simulate
                </button>
                <button type="button" class="btn btn-ghost btn-sm" phx-click="reset">Reset</button>
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
            <div class="alert">
              <.icon name="hero-information-circle" class="size-5" />
              <span>Fill in the form and click Simulate to see a decision and per-policy trace.</span>
            </div>
          <% end %>
        </section>
      </div>

      <%= if @result do %>
        <section class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title text-lg flex items-center gap-2">
              <.icon name="hero-queue-list" class="size-5" /> Trace
              <span class="badge badge-ghost">{length(@result.traces)}</span>
            </h2>
            <.trace_table traces={@result.traces} winner_id={@result.winner_id} />
          </div>
        </section>
      <% end %>
    </div>
    """
  end
end
