defmodule EyeInTheSkyWeb.PromptLive.Show do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Prompts
  import EyeInTheSkyWeb.Helpers.ViewHelpers

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, sidebar_tab: :prompts, sidebar_project: nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    prompt = Prompts.get_prompt_by_uuid!(id)

    socket =
      socket
      |> assign(:page_title, "Prompt: #{prompt.name}")
      |> assign(:prompt, prompt)
      |> assign(:editing, false)
      |> assign(:form, to_form(Prompts.change_prompt(prompt)))

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply, assign(socket, :editing, true)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    # Reset form to current prompt values
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
    case Prompts.deactivate_prompt(socket.assigns.prompt) do
      {:ok, _prompt} ->
        {:noreply,
         socket
         |> put_flash(:info, "Prompt deactivated successfully")
         |> push_navigate(to: ~p"/prompts")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to deactivate prompt")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <!-- Header with back button -->
      <div class="mb-6">
        <.link navigate={~p"/prompts"} class="btn btn-ghost btn-sm gap-2">
          <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M10 19l-7-7m0 0l7-7m-7 7h18"
            />
          </svg>
          Back to Prompts
        </.link>
      </div>
      
    <!-- Prompt Header -->
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
          <label class="swap swap-rotate btn btn-ghost btn-sm btn-circle">
            <input type="checkbox" class="theme-controller" value="dark" />
            <svg class="swap-on h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z"
              />
            </svg>
            <svg class="swap-off h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z"
              />
            </svg>
          </label>

          <%= if @editing do %>
            <button
              phx-click="cancel_edit"
              class="btn btn-ghost btn-sm"
            >
              Cancel
            </button>
          <% else %>
            <button
              phx-click="edit"
              class="btn btn-primary btn-sm"
            >
              <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
                />
              </svg>
              Edit
            </button>
            <button
              phx-click="delete"
              class="btn btn-error btn-sm"
              data-confirm="Are you sure you want to deactivate this prompt?"
            >
              <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                />
              </svg>
              Deactivate
            </button>
          <% end %>
        </div>
      </div>
      
    <!-- Metadata Cards -->
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4 mb-6">
        <div class="card bg-base-200">
          <div class="card-body p-4">
            <div class="text-xs text-base-content/50 uppercase font-semibold">Slug</div>
            <code class="text-sm font-mono mt-1">{@prompt.slug}</code>
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body p-4">
            <div class="text-xs text-base-content/50 uppercase font-semibold">
              Version
            </div>
            <div class="text-lg font-semibold mt-1">v{@prompt.version}</div>
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body p-4">
            <div class="text-xs text-base-content/50 uppercase font-semibold">
              Created
            </div>
            <div class="text-sm mt-1" title={format_datetime_full(@prompt.created_at)}>
              {relative_time(@prompt.created_at)}
            </div>
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body p-4">
            <div class="text-xs text-base-content/50 uppercase font-semibold">
              Updated
            </div>
            <div class="text-sm mt-1" title={format_datetime_full(@prompt.updated_at)}>
              {relative_time(@prompt.updated_at)}
            </div>
          </div>
        </div>
      </div>
      
    <!-- Prompt Text Card / Edit Form -->
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
      
    <!-- Additional Info (if available) -->
      <%= if @prompt.tags || @prompt.created_by || @prompt.project_id do %>
        <div class="card bg-base-100 shadow-xl mt-6">
          <div class="card-body">
            <h2 class="card-title text-lg">Additional Information</h2>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 mt-4">
              <%= if @prompt.tags do %>
                <div>
                  <div class="text-xs text-base-content/50 uppercase font-semibold mb-2">
                    Tags
                  </div>
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
    </div>
    """
  end
end
