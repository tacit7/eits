defmodule EyeInTheSkyWeb.Components.NewSessionModal do
  @moduledoc """
  Centered modal dialog for creating new sessions/agents.
  Context-aware: pre-fills project when launched from a project page.
  """

  use Phoenix.LiveComponent
  import EyeInTheSkyWeb.CoreComponents, only: [icon: 1, modal_header: 1]
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [models_for_provider: 1]
  import EyeInTheSkyWeb.Helpers.ModelHelpers, only: [normalize_model_alias: 1]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.Claude.AgentFileScanner
  alias EyeInTheSky.Projects
  alias EyeInTheSky.Settings

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       selected_model: default_claude_model(),
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
    if socket.assigns[:show] && assigns[:show] do
      new_uploads = Map.get(assigns, :file_uploads)

      if socket.assigns[:file_uploads] == new_uploads do
        {:ok, socket}
      else
        {:ok, assign(socket, :file_uploads, new_uploads)}
      end
    else
      project_path = if assigns[:current_project], do: assigns[:current_project].path
      available_agents = Map.get_lazy(assigns, :available_agents, fn -> list_agents(project_path) end)

      {:ok, assign(socket, Map.put(assigns, :available_agents, available_agents))}
    end
  end

  @impl true
  def handle_event("provider_changed", %{"agent_type" => provider}, socket) do
    default_model =
      if provider == "codex",
        do: EyeInTheSky.Agents.ModelConfig.default_model("codex"),
        else: default_claude_model()
    {:noreply, assign(socket, selected_provider: provider, selected_model: default_model)}
  end

  def handle_event("model_changed", %{"model" => model}, socket) do
    {:noreply, assign(socket, :selected_model, model)}
  end

  def handle_event("prompt_selected", %{"prompt_id" => ""}, socket) do
    {:noreply, assign(socket, selected_prompt_id: nil, prefill_text: "")}
  end

  def handle_event("project_changed", %{"project_id" => project_id_str}, socket) do
    project_path =
      case parse_int(project_id_str) do
        nil ->
          nil

        id ->
          case Projects.get_project(id) do
            {:ok, project} -> project.path
            {:error, :not_found} -> nil
          end
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
      <div
        :if={@show}
        class="modal modal-open modal-bottom sm:modal-middle"
        phx-window-keydown={@toggle_event}
        phx-key="Escape"
      >
        <div class="modal-box w-full sm:max-w-md pb-[env(safe-area-inset-bottom)]">
          <.modal_header title={assigns[:title] || "New Agent"} toggle_event={@toggle_event} />

          <form phx-submit={@submit_event} class="flex flex-col gap-4">
            <.provider_field selected_provider={@selected_provider} myself={@myself} />
            <.agent_combobox available_agents={@available_agents} />
            <.prompt_selector prompts={assigns[:prompts]} selected_prompt_id={@selected_prompt_id} myself={@myself} />
            <.name_field />
            <.description_field selected_prompt_id={@selected_prompt_id} prefill_text={@prefill_text} />
            <.image_attachments file_uploads={@file_uploads} />
            <.project_selector current_project={assigns[:current_project]} projects={assigns[:projects]} myself={@myself} />
            <.model_selector selected_provider={@selected_provider} selected_model={@selected_model} myself={@myself} />
            <.effort_selector selected_provider={@selected_provider} selected_model={@selected_model} />
            <.worktree_field />
            <.eits_workflow_field />
            <.cli_flags_section />
            <.modal_submit button_text={assigns[:button_text]} />
          </form>
        </div>
        <div class="modal-backdrop bg-black/50 cursor-pointer" phx-click={@toggle_event}></div>
      </div>
    </div>
    """
  end

  attr :selected_provider, :string, required: true
  attr :myself, :any, required: true

  defp provider_field(assigns) do
    ~H"""
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
    """
  end

  attr :available_agents, :list, required: true

  defp agent_combobox(assigns) do
    ~H"""
    <%= if @available_agents != [] do %>
      <div
        id="agent-combobox"
        phx-hook="AgentCombobox"
        data-agents={Jason.encode!(Enum.map(@available_agents, fn {slug, name, scope} -> [slug, name, to_string(scope)] end))}
        class="relative"
      >
        <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Agent</label>
        <%!-- Hidden field carries the selected slug to the form submit --%>
        <input type="hidden" name="agent" data-combobox-value />
        <%!-- Visible search input — not submitted, value used only for display --%>
        <input
          type="text"
          data-combobox-input
          placeholder="Search agents..."
          autocomplete="off"
          role="combobox"
          aria-autocomplete="list"
          aria-controls="agent-combobox-list"
          aria-expanded="false"
          class="input input-bordered w-full text-base"
        />
        <ul
          id="agent-combobox-list"
          data-combobox-list
          role="listbox"
          class="hidden absolute z-20 mt-1 w-full bg-base-200 border border-base-300 rounded-box shadow-lg max-h-60 overflow-y-auto"
        ></ul>
      </div>
    <% end %>
    """
  end

  attr :prompts, :list, default: nil
  attr :selected_prompt_id, :any, required: true
  attr :myself, :any, required: true

  defp prompt_selector(assigns) do
    ~H"""
    <%= if (@prompts || []) != [] do %>
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
    """
  end

  defp name_field(assigns) do
    ~H"""
    <div>
      <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Name</label>
      <input
        type="text"
        name="agent_name"
        class="input input-bordered w-full text-base"
        placeholder="e.g., Fix login bug, Code review..."
      />
    </div>
    """
  end

  attr :selected_prompt_id, :any, required: true
  attr :prefill_text, :string, required: true

  defp description_field(assigns) do
    ~H"""
    <div>
      <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Description</label>
      <textarea
        id={"desc-#{@selected_prompt_id || "none"}"}
        name="description"
        class="textarea textarea-bordered w-full h-20 text-base"
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
    """
  end

  attr :file_uploads, :any, default: nil

  defp image_attachments(assigns) do
    ~H"""
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
    """
  end

  attr :current_project, :any, default: nil
  attr :projects, :list, default: nil
  attr :myself, :any, required: true

  defp project_selector(assigns) do
    ~H"""
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
    """
  end

  attr :selected_provider, :string, required: true
  attr :selected_model, :string, required: true
  attr :myself, :any, required: true

  defp model_selector(assigns) do
    ~H"""
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
    """
  end

  attr :selected_provider, :string, required: true
  attr :selected_model, :string, required: true

  defp effort_selector(assigns) do
    ~H"""
    <%= if @selected_provider == "claude" and (String.starts_with?(@selected_model, "claude-opus") or @selected_model in ["opus", "opus[1m]"]) do %>
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
    """
  end

  defp worktree_field(assigns) do
    ~H"""
    <div>
      <label class="text-sm font-medium text-base-content/70 mb-1.5 block">
        Worktree Branch
        <span class="text-xs font-normal text-base-content/40 ml-1">Optional</span>
      </label>
      <input
        type="text"
        name="worktree"
        class="input input-bordered w-full font-mono text-base"
        placeholder="e.g., fix-login-bug"
      />
      <p class="text-xs text-base-content/35 mt-1">
        Isolates work in its own branch (worktree-&lt;name&gt;) and enables automatic PR creation.
      </p>
    </div>
    """
  end

  defp eits_workflow_field(assigns) do
    ~H"""
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
    """
  end

  defp cli_flags_section(assigns) do
    ~H"""
    <div class="collapse collapse-arrow bg-base-200 rounded-lg">
      <input type="checkbox" class="min-h-0" />
      <div class="collapse-title min-h-0 py-2.5 px-3 flex items-center gap-1.5 text-xs font-medium text-base-content/60">
        <.icon name="hero-adjustments-horizontal" class="w-3.5 h-3.5" /> Advanced
      </div>
      <div class="collapse-content px-3 pb-3 space-y-3">
        <div class="form-control">
          <label class="label"><span class="label-text text-xs">Permission Mode</span></label>
          <select name="permission_mode" class="select select-bordered select-sm w-full">
            <option value="">Default</option>
            <option value="acceptEdits">acceptEdits — auto-accept file edits</option>
            <option value="bypassPermissions">bypassPermissions — skip all prompts</option>
            <option value="dontAsk">dontAsk — never ask for confirmation</option>
            <option value="plan">plan — read-only, no file changes</option>
          </select>
        </div>

        <div class="form-control">
          <label class="label">
            <span class="label-text text-xs">Max Turns</span>
            <span class="label-text-alt text-base-content/40 font-mono text-xs">
              --max-turns
            </span>
          </label>
          <input
            type="number"
            name="max_turns"
            min="1"
            placeholder="unlimited"
            class="input input-bordered input-sm w-full font-mono min-h-[44px]"
          />
        </div>

        <div class="form-control">
          <label class="label">
            <span class="label-text text-xs">Add Directory</span>
            <span class="label-text-alt text-base-content/40 font-mono text-xs">
              --add-dir
            </span>
          </label>
          <input
            type="text"
            name="add_dir"
            placeholder="/path/to/shared-lib"
            class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
          />
        </div>

        <div class="form-control">
          <label class="label">
            <span class="label-text text-xs">MCP Config File</span>
            <span class="label-text-alt text-base-content/40 font-mono text-xs">
              --mcp-config
            </span>
          </label>
          <input
            type="text"
            name="mcp_config"
            placeholder="./mcp-servers.json"
            class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
          />
        </div>

        <div class="form-control">
          <label class="label">
            <span class="label-text text-xs">Plugin Directory</span>
            <span class="label-text-alt text-base-content/40 font-mono text-xs">
              --plugin-dir
            </span>
          </label>
          <input
            type="text"
            name="plugin_dir"
            placeholder="./my-plugins"
            class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
          />
        </div>

        <div class="form-control">
          <label class="label">
            <span class="label-text text-xs">Settings File</span>
            <span class="label-text-alt text-base-content/40 font-mono text-xs">
              --settings
            </span>
          </label>
          <input
            type="text"
            name="settings_file"
            placeholder="./settings.json"
            class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
          />
        </div>

        <div class="flex flex-col gap-1 pt-1">
          <label class="label cursor-pointer justify-start gap-2 py-1">
            <input
              type="checkbox"
              name="chrome"
              value="true"
              class="checkbox checkbox-sm checkbox-primary"
            />
            <span class="label-text text-xs">
              Chrome integration
              <span class="font-mono text-base-content/40 text-xs ml-1">--chrome</span>
            </span>
          </label>
          <label class="label cursor-pointer justify-start gap-2 py-1">
            <input
              type="checkbox"
              name="sandbox"
              value="true"
              class="checkbox checkbox-sm checkbox-primary"
            />
            <span class="label-text text-xs">
              OS sandbox isolation
              <span class="font-mono text-base-content/40 text-xs ml-1">--sandbox</span>
            </span>
          </label>
        </div>
      </div>
    </div>
    """
  end

  attr :button_text, :string, default: nil

  defp modal_submit(assigns) do
    ~H"""
    <button type="submit" class="btn btn-primary w-full mt-2">
      {@button_text || "Create Agent"}
    </button>
    """
  end

  defp default_claude_model do
    Settings.get("default_model") |> normalize_model_alias()
  end

  defp list_agents(project_path) do
    AgentFileScanner.scan(project_path)
    |> Enum.map(fn agent -> {agent.slug, agent.name, agent.source} end)
  end
end
