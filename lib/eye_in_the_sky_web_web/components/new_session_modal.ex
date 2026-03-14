defmodule EyeInTheSkyWebWeb.Components.NewSessionModal do
  @moduledoc """
  Centered modal dialog for creating new sessions/agents.
  Context-aware: pre-fills project when launched from a project page.
  """

  use Phoenix.LiveComponent
  import EyeInTheSkyWebWeb.CoreComponents, only: [icon: 1]
  import EyeInTheSkyWebWeb.Helpers.ViewHelpers, only: [claude_models: 0, codex_models: 0]

  @global_agents_dir Path.expand("~/.claude/agents")

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       selected_model: "sonnet",
       selected_provider: "claude",
       selected_prompt_id: nil,
       prefill_text: "",
       available_agents: []
     )}
  end

  @impl true
  def update(assigns, socket) do
    project_path = assigns[:current_project] && assigns[:current_project].path
    available_agents = list_agents(project_path)
    {:ok, assign(socket, Map.put(assigns, :available_agents, available_agents))}
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

    {:noreply, assign(socket, selected_prompt_id: prompt_id, prefill_text: prefill)}
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

            <%!-- Agent --%>
            <%= if length(@available_agents) > 0 do %>
              <div>
                <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Agent</label>
                <select name="agent" class="select select-bordered w-full">
                  <option value="">-- None --</option>
                  <%= for {name, scope} <- @available_agents do %>
                    <option value={name}>{name}<%= if scope == :project, do: " (project)" %></option>
                  <% end %>
                </select>
              </div>
            <% end %>

            <%!-- Agent Prompt (when prompts exist) --%>
            <%= if length(assigns[:prompts] || []) > 0 do %>
              <div>
                <label class="text-sm font-medium text-base-content/70 mb-1.5 block">
                  Agent Prompt
                </label>
                <select
                  name="prompt_id"
                  class="select select-bordered w-full"
                  phx-change="prompt_selected"
                  phx-target={@myself}
                >
                  <option value="">-- None --</option>
                  <%= for prompt <- @prompts do %>
                    <option
                      value={prompt.id}
                      selected={to_string(@selected_prompt_id) == to_string(prompt.id)}
                    >
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
                id={"desc-#{@selected_prompt_id || "none"}"}
                name="description"
                class="textarea textarea-bordered w-full h-20 text-sm"
                placeholder="What should this agent work on?"
                required
                autofocus
                phx-update="ignore"
                phx-mounted={Phoenix.LiveView.JS.dispatch("focus")}
              >{@prefill_text}</textarea>
              <label class="flex items-center gap-1.5 mt-2 cursor-pointer w-fit">
                <.icon name="hero-paper-clip-mini" class="w-3.5 h-3.5 text-base-content/40" />
                <span class="text-xs text-base-content/40 hover:text-base-content/60 transition-colors">Attach file</span>
                <input
                  type="file"
                  class="hidden"
                  accept=".txt,.md,.json,.yaml,.yml,.ex,.exs,.js,.ts,.py,.sh,.csv,.xml,.toml"
                  phx-hook="FileAttach"
                  id={"file-attach-#{@selected_prompt_id || "none"}"}
                  data-target={"desc-#{@selected_prompt_id || "none"}"}
                />
              </label>
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

            <%!-- Worktree Branch (optional) --%>
            <div>
              <label class="text-sm font-medium text-base-content/70 mb-1.5 block">
                Worktree Branch
                <span class="text-xs font-normal text-base-content/40 ml-1">Optional</span>
              </label>
              <input
                type="text"
                name="worktree"
                class="input input-bordered w-full font-mono text-sm"
                placeholder="e.g., fix-login-bug"
              />
              <p class="text-xs text-base-content/35 mt-1">
                Isolates work in its own branch (worktree-&lt;name&gt;) and enables automatic PR creation.
              </p>
            </div>

            <%!-- Submit --%>
            <button type="submit" class="btn btn-primary w-full mt-2">
              {assigns[:button_text] || "Create Agent"}
            </button>
          </form>
        </div>
        <div class="modal-backdrop bg-black/50 cursor-pointer" phx-click={@toggle_event}></div>
      </div>
    </div>
    """
  end

  defp models_for_provider("codex"), do: codex_models()
  defp models_for_provider(_), do: claude_models()

  # Returns [{name, scope}] where scope is :project or :global.
  # Project agents take priority and are listed first; duplicates deduped by name.
  defp list_agents(project_path) do
    project_agents =
      if project_path do
        dir = Path.join([project_path, ".claude", "agents"])
        scan_agent_dir(dir, :project)
      else
        []
      end

    global_agents = scan_agent_dir(@global_agents_dir, :global)

    project_names = MapSet.new(project_agents, fn {name, _} -> name end)

    deduped_global =
      Enum.reject(global_agents, fn {name, _} -> MapSet.member?(project_names, name) end)

    project_agents ++ deduped_global
  end

  defp scan_agent_dir(dir, scope) do
    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".md"))
      |> Enum.reject(&(&1 == "README.md"))
      |> Enum.map(fn filename ->
        name = Path.rootname(filename)
        {name, scope}
      end)
      |> Enum.sort_by(fn {name, _} -> name end)
    else
      []
    end
  end
end
