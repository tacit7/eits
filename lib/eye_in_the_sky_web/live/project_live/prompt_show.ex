defmodule EyeInTheSkyWeb.ProjectLive.PromptShow do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Prompts
  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  import EyeInTheSkyWeb.Helpers.ViewHelpers

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    socket = mount_project(socket, params, sidebar_tab: :prompts, page_title_prefix: "Prompt")
    {:ok, assign(socket, editing: false, prompt: nil, form: nil)}
  end

  @impl true
  def handle_params(%{"prompt_id" => prompt_uuid} = _params, _url, socket) do
    prompt = Prompts.get_prompt_by_uuid!(prompt_uuid)

    project = socket.assigns.project

    if prompt.project_id && project && prompt.project_id != to_string(project.id) do
      {:noreply,
       socket
       |> put_flash(:error, "Prompt not found in this project")
       |> push_navigate(to: ~p"/projects/#{project.id}/prompts")}
    else
      socket =
        socket
        |> assign(:page_title, "Prompt: #{prompt.name}")
        |> assign(:prompt, prompt)
        |> assign(:editing, false)
        |> assign(:form, to_form(Prompts.change_prompt(prompt)))

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply, assign(socket, :editing, true)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    socket =
      socket
      |> assign(:editing, false)
      |> assign(:form, to_form(Prompts.change_prompt(socket.assigns.prompt)))

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"prompt" => prompt_params}, socket) do
    changeset =
      socket.assigns.prompt
      |> Prompts.change_prompt(prompt_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"prompt" => prompt_params}, socket) do
    case Prompts.update_prompt(socket.assigns.prompt, prompt_params) do
      {:ok, updated_prompt} ->
        socket =
          socket
          |> assign(:prompt, updated_prompt)
          |> assign(:editing, false)
          |> assign(:form, to_form(Prompts.change_prompt(updated_prompt)))
          |> put_flash(:info, "Prompt updated successfully")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    project = socket.assigns.project

    case Prompts.deactivate_prompt(socket.assigns.prompt) do
      {:ok, _prompt} ->
        return_to =
          if project,
            do: ~p"/projects/#{project.id}/prompts",
            else: ~p"/"

        {:noreply,
         socket
         |> put_flash(:info, "Prompt deactivated successfully")
         |> push_navigate(to: return_to)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to deactivate prompt")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <div class="mb-6">
        <%= if @project do %>
          <.link navigate={~p"/projects/#{@project.id}/prompts"} class="btn btn-ghost btn-sm gap-2">
            <.icon name="hero-arrow-left" class="h-4 w-4" /> Back to Prompts
          </.link>
        <% end %>
      </div>

      <%= if @prompt do %>
        <div class="sm:flex sm:items-center sm:justify-between mb-6">
          <div class="sm:flex-auto">
            <div class="flex items-center gap-3">
              <h1 class="text-2xl font-semibold leading-6 text-base-content">
                {@prompt.name}
              </h1>
              <%= if is_nil(@prompt.project_id) do %>
                <span class="badge badge-primary">Global</span>
              <% else %>
                <span class="badge badge-secondary">Project</span>
              <% end %>
              <span class="badge badge-ghost">v{@prompt.version}</span>
            </div>

            <%= if @prompt.description do %>
              <p class="mt-2 text-sm text-base-content/70">
                {@prompt.description}
              </p>
            <% end %>
          </div>

          <div class="mt-4 sm:mt-0 flex items-center gap-2">
            <%= if @editing do %>
              <button phx-click="cancel_edit" class="btn btn-ghost btn-sm">
                Cancel
              </button>
            <% else %>
              <button phx-click="edit" class="btn btn-primary btn-sm">
                <.icon name="hero-pencil-square" class="h-4 w-4" /> Edit
              </button>
              <button
                phx-click="delete"
                class="btn btn-error btn-sm"
                data-confirm="Are you sure you want to deactivate this prompt?"
              >
                <.icon name="hero-trash" class="h-4 w-4" /> Deactivate
              </button>
            <% end %>
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4 mb-6">
          <div class="card bg-base-200">
            <div class="card-body p-4">
              <div class="text-xs text-base-content/50 uppercase font-semibold">Slug</div>
              <code class="text-sm font-mono mt-1">{@prompt.slug}</code>
            </div>
          </div>

          <div class="card bg-base-200">
            <div class="card-body p-4">
              <div class="text-xs text-base-content/50 uppercase font-semibold">Version</div>
              <div class="text-lg font-semibold mt-1">v{@prompt.version}</div>
            </div>
          </div>

          <div class="card bg-base-200">
            <div class="card-body p-4">
              <div class="text-xs text-base-content/50 uppercase font-semibold">Created</div>
              <div class="text-sm mt-1" title={format_datetime_full(@prompt.created_at)}>
                {relative_time(@prompt.created_at)}
              </div>
            </div>
          </div>

          <div class="card bg-base-200">
            <div class="card-body p-4">
              <div class="text-xs text-base-content/50 uppercase font-semibold">Updated</div>
              <div class="text-sm mt-1" title={format_datetime_full(@prompt.updated_at)}>
                {relative_time(@prompt.updated_at)}
              </div>
            </div>
          </div>
        </div>

        <%= if @editing do %>
          <.form
            for={@form}
            phx-change="validate"
            phx-submit="save"
            class="card bg-base-100 shadow-xl"
          >
            <div class="card-body">
              <h2 class="card-title text-lg">Edit Prompt</h2>

              <div class="form-control mt-4">
                <label class="label">
                  <span class="label-text font-semibold">Name</span>
                </label>
                <.input field={@form[:name]} type="text" />
              </div>

              <div class="form-control mt-4">
                <label class="label">
                  <span class="label-text font-semibold">Slug</span>
                </label>
                <.input field={@form[:slug]} type="text" />
              </div>

              <div class="form-control mt-4">
                <label class="label">
                  <span class="label-text font-semibold">Description</span>
                </label>
                <.input field={@form[:description]} type="text" />
              </div>

              <div class="form-control mt-4">
                <label class="label">
                  <span class="label-text font-semibold">Prompt Text</span>
                </label>
                <.input
                  field={@form[:prompt_text]}
                  type="textarea"
                  rows="20"
                  class="font-mono text-sm"
                  phx-debounce="blur"
                />
              </div>

              <div class="card-actions justify-end mt-6">
                <button type="button" phx-click="cancel_edit" class="btn btn-ghost">
                  Cancel
                </button>
                <button type="submit" class="btn btn-primary">
                  Save Changes
                </button>
              </div>
            </div>
          </.form>
        <% else %>
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h2 class="card-title text-lg">Prompt Text</h2>
              <div class="mockup-code mt-4">
                <pre class="px-6 py-4 whitespace-pre-wrap break-words"><code>{@prompt.prompt_text}</code></pre>
              </div>
            </div>
          </div>
        <% end %>

        <%= if @prompt.tags || @prompt.created_by || @prompt.project_id do %>
          <div class="card bg-base-100 shadow-xl mt-6">
            <div class="card-body">
              <h2 class="card-title text-lg">Additional Information</h2>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 mt-4">
                <%= if @prompt.tags do %>
                  <div>
                    <div class="text-xs text-base-content/50 uppercase font-semibold mb-2">Tags</div>
                    <div class="text-sm">{@prompt.tags}</div>
                  </div>
                <% end %>

                <%= if @prompt.created_by do %>
                  <div>
                    <div class="text-xs text-base-content/50 uppercase font-semibold mb-2">
                      Created By
                    </div>
                    <div class="text-sm">{@prompt.created_by}</div>
                  </div>
                <% end %>

                <%= if @prompt.project_id do %>
                  <div>
                    <div class="text-xs text-base-content/50 uppercase font-semibold mb-2">
                      Project ID
                    </div>
                    <div class="text-sm font-mono">{@prompt.project_id}</div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
