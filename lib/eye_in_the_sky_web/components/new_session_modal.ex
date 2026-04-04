defmodule EyeInTheSkyWeb.Components.NewSessionModal do
  @moduledoc """
  Centered modal dialog for creating new sessions/agents.
  Context-aware: pre-fills project when launched from a project page.
  """

  use Phoenix.LiveComponent
  import EyeInTheSkyWeb.CoreComponents, only: [icon: 1, modal_header: 1]
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [models_for_provider: 1]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.Claude.AgentFileScanner

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       selected_model: "sonnet",
       selected_provider: "claude",
       selected_prompt_id: nil,
       prefill_text: "",
       available_agents: [],
       file_uploads: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    # When the form is open, skip parent re-renders entirely to prevent DOM patches from
    # disrupting the modal (e.g. PubSub-driven list updates closing the form). Only update
    # uploads when they actually change so image previews stay current.
    if socket.assigns[:show] == true && assigns[:show] == true do
      new_uploads = Map.get(assigns, :file_uploads)

      if socket.assigns[:file_uploads] == new_uploads do
        {:ok, socket}
      else
        {:ok, assign(socket, :file_uploads, new_uploads)}
      end
    else
      project_path = assigns[:current_project] && assigns[:current_project].path
      available_agents = list_agents(project_path)
      {:ok, assign(socket, Map.put(assigns, :available_agents, available_agents))}
    end
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

  def handle_event("project_changed", %{"project_id" => project_id_str}, socket) do
    projects = socket.assigns[:projects] || []

    project_path =
      case parse_int(project_id_str) do
        nil -> nil
        id ->
          project = Enum.find(projects, fn p -> p.id == id end)
          project && project.path
      end

    {:noreply, assign(socket, :available_agents, list_agents(project_path))}
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
          <.modal_header title={assigns[:title] || "New Agent"} toggle_event={@toggle_event} />

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
                  <%= for {slug, name, scope} <- @available_agents do %>
                    <option value={slug}>{name}{if scope == :project, do: " (project)"}</option>
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

            <%!-- Name --%>
            <div>
              <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Name</label>
              <input
                type="text"
                name="agent_name"
                class="input input-bordered w-full"
                placeholder="e.g., Fix login bug, Code review..."
              />
            </div>

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
                <span class="text-xs text-base-content/40 hover:text-base-content/60 transition-colors">
                  Attach file
                </span>
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

            <%!-- Image attachments --%>
            <%= if @file_uploads && Map.has_key?(@file_uploads, :agent_images) do %>
              <div>
                <%= if @file_uploads.agent_images.entries != [] do %>
                  <div class="flex flex-wrap gap-2 mb-2">
                    <%= for entry <- @file_uploads.agent_images.entries do %>
                      <div class="flex items-center gap-1.5 rounded-lg bg-base-content/[0.04] px-2 py-1 text-xs">
                        <.icon name="hero-photo" class="w-3.5 h-3.5 text-base-content/40" />
                        <span class="text-base-content/70">{entry.client_name}</span>
                        <button
                          type="button"
                          phx-click="cancel_agent_upload"
                          phx-value-ref={entry.ref}
                          class="text-base-content/30 hover:text-error transition-colors"
                        >
                          <.icon name="hero-x-mark-mini" class="w-3.5 h-3.5" />
                        </button>
                      </div>
                    <% end %>
                  </div>
                <% end %>
                <label
                  for={@file_uploads.agent_images.ref}
                  phx-drop-target={@file_uploads.agent_images.ref}
                  class="flex items-center gap-1.5 cursor-pointer w-fit"
                >
                  <.icon name="hero-photo-mini" class="w-3.5 h-3.5 text-base-content/40" />
                  <span class="text-xs text-base-content/40 hover:text-base-content/60 transition-colors">
                    Attach image
                  </span>
                </label>
                <.live_file_input upload={@file_uploads.agent_images} class="hidden" />
              </div>
            <% end %>

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
                <select
                  name="project_id"
                  class="select select-bordered w-full"
                  required
                  phx-change="project_changed"
                  phx-target={@myself}
                >
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
                  <option value="max">Max</option>
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

            <%!-- EITS Workflow --%>
            <label class="flex items-center gap-2 cursor-pointer select-none">
              <input type="hidden" name="eits_workflow" value="0" />
              <input
                type="checkbox"
                name="eits_workflow"
                value="1"
                class="checkbox checkbox-sm"
                checked
              />
              <span class="text-sm text-base-content/70">EITS Workflow</span>
            </label>

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

  defp list_agents(project_path) do
    AgentFileScanner.scan(project_path)
    |> Enum.map(fn agent -> {agent.slug, agent.name, agent.source} end)
  end
end
