defmodule EyeInTheSkyWeb.Components.AIJobCreator do
  @moduledoc """
  LiveComponent for the Claude AI job creation drawer.

  Manages its own show_claude_drawer / claude_model state.
  The "Create with Claude" buttons in jobs_page target jobs_page @myself,
  which relays via send_update(AIJobCreator, action: :toggle_drawer).
  Buttons inside the drawer itself target this component's @myself directly.
  """

  use EyeInTheSkyWeb, :live_component

  import EyeInTheSkyWeb.Live.Shared.JobsHelpers,
    only: [
      handle_toggle_claude_drawer: 2,
      handle_claude_model_changed: 2,
      handle_create_with_claude: 4
    ]

  alias EyeInTheSky.Projects

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  @impl true
  # Relay from jobs_page: toggle open/close without passing params
  def update(%{action: :toggle_drawer}, socket) do
    current = Map.get(socket.assigns, :show_claude_drawer, false)
    {:ok, assign(socket, :show_claude_drawer, !current)}
  end

  def update(assigns, socket) do
    initialized = Map.has_key?(socket.assigns, :show_claude_drawer)
    prev_project_id = Map.get(socket.assigns, :project_id)

    socket =
      socket
      |> assign(:project_id, assigns.project_id)
      |> assign(:project, assigns.project)

    socket =
      if not initialized do
        socket
        |> assign(:show_claude_drawer, false)
        |> assign(:claude_model, "sonnet")
        |> maybe_assign_web_project(assigns.project_id)
      else
        # Refresh web_project if project context changed
        if assigns.project_id != prev_project_id do
          maybe_assign_web_project(socket, assigns.project_id)
        else
          socket
        end
      end

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events (all buttons inside the drawer target @myself directly)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event(event, params, socket) do
    dispatch_event(event, params, socket)
  end

  defp dispatch_event("toggle_claude_drawer", params, socket),
    do: handle_toggle_claude_drawer(params, socket)

  defp dispatch_event("claude_model_changed", params, socket),
    do: handle_claude_model_changed(params, socket)

  defp dispatch_event("create_with_claude", params, socket) do
    if socket.assigns.project_id do
      handle_create_with_claude(params, socket, socket.assigns.project,
        prompt_project: socket.assigns.project
      )
    else
      handle_create_with_claude(params, socket, socket.assigns.web_project,
        error_msg: "EITS Web project not found"
      )
    end
  end

  defp dispatch_event(_event, _params, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp maybe_assign_web_project(socket, nil) do
    web_project =
      case Projects.get_project_by_name("EITS Web") do
        {:ok, project} -> project
        {:error, :not_found} -> nil
      end

    assign(socket, :web_project, web_project)
  end

  defp maybe_assign_web_project(socket, _project_id), do: socket

  # ---------------------------------------------------------------------------
  # Template
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Claude Create Drawer --%>
      <div class={[
        "fixed inset-y-0 right-0 safe-inset-y z-50 w-full max-w-sm bg-base-100 shadow-xl transform transition-transform duration-200 ease-in-out overflow-y-auto",
        if(@show_claude_drawer, do: "translate-x-0", else: "translate-x-full")
      ]}>
        <div class="p-6">
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-lg font-semibold">Create Job with Claude</h2>
            <button
              class="btn btn-ghost btn-sm btn-square"
              phx-click="toggle_claude_drawer"
              phx-target={@myself}
            >
              <span class="sr-only">Close Claude drawer</span>
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          </div>
          <form phx-submit="create_with_claude" phx-target={@myself} class="flex flex-col gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Model</span></label>
              <select
                name="model"
                class="select select-bordered w-full"
                phx-change="claude_model_changed"
                phx-target={@myself}
              >
                <option value="opus" selected={@claude_model == "opus"}>
                  Opus 4.6 &bull; Most capable for complex work
                </option>
                <option value="sonnet" selected={@claude_model == "sonnet"}>
                  Sonnet 4.5 &bull; Best for everyday tasks
                </option>
                <option value="sonnet[1m]" selected={@claude_model == "sonnet[1m]"}>
                  Sonnet 4.5 (1M) &bull; 1M context window
                </option>
                <option value="haiku" selected={@claude_model == "haiku"}>
                  Haiku 4.5 &bull; Fastest for quick answers
                </option>
              </select>
            </div>
            <%= if @claude_model == "opus" do %>
              <div class="form-control">
                <label class="label"><span class="label-text font-medium">Effort Level</span></label>
                <select name="effort_level" class="select select-bordered w-full">
                  <option value="" selected>Default (high)</option>
                  <option value="low">Low</option>
                  <option value="medium">Medium</option>
                  <option value="high">High</option>
                  <option value="max">Max</option>
                </select>
              </div>
            <% end %>
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Description</span></label>
              <textarea
                name="description"
                class="textarea textarea-bordered w-full text-base"
                rows="3"
                placeholder="What kind of job do you want to create?"
              ></textarea>
            </div>
            <div class="flex gap-2 mt-4">
              <button type="submit" class="btn btn-primary flex-1">Start</button>
              <button
                type="button"
                phx-click="toggle_claude_drawer"
                phx-target={@myself}
                class="btn btn-ghost"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
      </div>
      <%= if @show_claude_drawer do %>
        <div
          class="fixed inset-0 z-40 bg-black/30"
          phx-click="toggle_claude_drawer"
          phx-target={@myself}
        >
        </div>
      <% end %>
    </div>
    """
  end
end
