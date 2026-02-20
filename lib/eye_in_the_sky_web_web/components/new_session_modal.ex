defmodule EyeInTheSkyWebWeb.Components.NewSessionModal do
  @moduledoc """
  Centered modal dialog for creating new sessions/agents.
  Context-aware: pre-fills project when launched from a project page.
  """

  use Phoenix.LiveComponent
  import EyeInTheSkyWebWeb.CoreComponents, only: [icon: 1]

  alias EyeInTheSkyWeb.Agents

  @claude_models [
    {"sonnet", "Sonnet 4.5"},
    {"opus", "Opus 4.6"},
    {"sonnet[1m]", "Sonnet 4.5 (1M)"},
    {"haiku", "Haiku 4.5"}
  ]

  @codex_models [
    {"gpt-5.3-codex", "GPT-5.3 Codex"},
    {"gpt-5.2-codex", "GPT-5.2 Codex"},
    {"gpt-5.2", "GPT-5.2"},
    {"gpt-5.1", "GPT-5.1"},
    {"gpt-5-codex-mini", "GPT-5 Codex Mini"}
  ]

  @impl true
  def mount(socket) do
    agent_templates =
      Agents.list_active_agents()
      |> Enum.filter(fn a -> a.description && a.description != "" end)
      |> Enum.take(50)
      |> Enum.map(fn a -> %{id: a.id, description: a.description} end)

    {:ok, assign(socket,
      selected_model: "sonnet",
      selected_provider: "claude",
      selected_prompt_id: nil,
      selected_agent_id: nil,
      prefill_text: "",
      agent_templates: agent_templates
    )}
  end

  @impl true
  def handle_event("provider_changed", %{"agent_type" => provider}, socket) do
    default_model = if provider == "codex", do: "gpt-5.3-codex", else: "sonnet"
    {:noreply, assign(socket, selected_provider: provider, selected_model: default_model)}
  end

  def handle_event("model_changed", %{"model" => model}, socket) do
    {:noreply, assign(socket, :selected_model, model)}
  end

  def handle_event("prompt_selected", %{"prompt_id" => ""}, socket) do
    {:noreply, assign(socket, selected_prompt_id: nil, prefill_text: "")}
  end

  def handle_event("prompt_selected", %{"prompt_id" => prompt_id}, socket) do
    prompts = socket.assigns[:prompts] || []
    prompt = Enum.find(prompts, fn p -> to_string(p.id) == prompt_id end)

    prefill = if prompt, do: prompt.prompt_text || "", else: ""
    {:noreply, assign(socket, selected_prompt_id: prompt_id, selected_agent_id: nil, prefill_text: prefill)}
  end

  def handle_event("agent_template_selected", %{"agent_id" => ""}, socket) do
    {:noreply, assign(socket, selected_agent_id: nil, prefill_text: "")}
  end

  def handle_event("agent_template_selected", %{"agent_id" => agent_id}, socket) do
    agents = socket.assigns[:agent_templates] || []
    agent = Enum.find(agents, fn a -> to_string(a.id) == agent_id end)

    prefill = if agent, do: agent.description || "", else: ""
    {:noreply, assign(socket, selected_agent_id: agent_id, selected_prompt_id: nil, prefill_text: prefill)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={@show} class="modal modal-open" phx-window-keydown={@toggle_event} phx-key="Escape">
        <div class="modal-box max-w-md">
          <div class="flex items-center justify-between mb-5">
            <h3 class="text-base font-semibold">{assigns[:title] || "New Agent"}</h3>
            <button phx-click={@toggle_event} class="btn btn-ghost btn-sm btn-circle">
              <.icon name="hero-x-mark-mini" class="w-4 h-4" />
            </button>
          </div>

          <form phx-submit={@submit_event} class="flex flex-col gap-4">
            <%!-- Agent Type --%>
            <div>
              <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Provider</label>
              <select
                name="agent_type"
                class="select select-bordered w-full"
                phx-change="provider_changed"
                phx-target={@myself}
              >
                <option value="claude" selected={@selected_provider == "claude"}>Claude</option>
                <option value="codex" selected={@selected_provider == "codex"}>Codex</option>
              </select>
            </div>

            <%!-- Copy from Agent --%>
            <%= if length(assigns[:agent_templates] || []) > 0 do %>
              <div>
                <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Copy from Agent</label>
                <select
                  name="agent_id"
                  class="select select-bordered w-full"
                  phx-change="agent_template_selected"
                  phx-target={@myself}
                >
                  <option value="">-- None --</option>
                  <%= for agent <- @agent_templates do %>
                    <option value={agent.id} selected={to_string(@selected_agent_id) == to_string(agent.id)}>
                      {agent.description}
                    </option>
                  <% end %>
                </select>
              </div>
            <% end %>

            <%!-- Agent Prompt (when prompts exist) --%>
            <%= if length(assigns[:prompts] || []) > 0 do %>
              <div>
                <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Agent Prompt</label>
                <select
                  name="prompt_id"
                  class="select select-bordered w-full"
                  phx-change="prompt_selected"
                  phx-target={@myself}
                >
                  <option value="">-- None --</option>
                  <%= for prompt <- @prompts do %>
                    <option value={prompt.id} selected={to_string(@selected_prompt_id) == to_string(prompt.id)}>
                      {prompt.name}
                    </option>
                  <% end %>
                </select>
              </div>
            <% end %>

            <%!-- Description --%>
            <div>
              <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Description</label>
              <textarea
                id={"desc-#{@selected_agent_id || @selected_prompt_id || "none"}"}
                name="description"
                class="textarea textarea-bordered w-full h-20 text-sm"
                placeholder="What should this agent work on?"
                required
                autofocus
                phx-mounted={Phoenix.LiveView.JS.dispatch("focus")}
              >{@prefill_text}</textarea>
            </div>

            <%!-- Project --%>
            <%= if @current_project do %>
              <input type="hidden" name="project_id" value={@current_project.id} />
              <div>
                <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Project</label>
                <div class="flex items-center gap-2 px-3 py-2.5 bg-base-200/50 rounded-lg text-sm text-base-content/70 border border-base-content/10">
                  <.icon name="hero-folder-mini" class="w-3.5 h-3.5 text-base-content/40" />
                  {@current_project.name}
                </div>
              </div>
            <% else %>
              <div>
                <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Project</label>
                <select name="project_id" class="select select-bordered w-full" required>
                  <option value="">Select project...</option>
                  <%= for project <- @projects || [] do %>
                    <option value={project.id}>{project.name}</option>
                  <% end %>
                </select>
              </div>
            <% end %>

            <%!-- Model --%>
            <div>
              <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Model</label>
              <select
                name="model"
                class="select select-bordered w-full"
                required
                phx-change="model_changed"
                phx-target={@myself}
              >
                <%= for {value, label} <- models_for_provider(@selected_provider) do %>
                  <option value={value} selected={@selected_model == value}>{label}</option>
                <% end %>
              </select>
            </div>

            <%!-- Effort (Claude Opus only) --%>
            <%= if @selected_provider == "claude" and @selected_model == "opus" do %>
              <div>
                <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Effort</label>
                <select name="effort_level" class="select select-bordered w-full">
                  <option value="">Default</option>
                  <option value="low">Low</option>
                  <option value="medium">Medium</option>
                  <option value="high">High</option>
                </select>
              </div>
            <% end %>

            <%!-- Submit --%>
            <button type="submit" class="btn btn-primary w-full mt-2">
              {assigns[:button_text] || "Create Agent"}
            </button>
          </form>
        </div>
        <div class="modal-backdrop" phx-click={@toggle_event}></div>
      </div>
    </div>
    """
  end

  defp models_for_provider("codex"), do: @codex_models
  defp models_for_provider(_), do: @claude_models
end
