defmodule EyeInTheSkyWeb.ProjectLive.PromptNew do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Prompts
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers
  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    socket = mount_project(socket, params, sidebar_tab: :prompts, page_title_prefix: "New Prompt")
    changeset = Prompts.change_prompt(%Prompts.Prompt{})

    {:ok, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  @impl true
  def handle_event("validate", %{"prompt" => prompt_params}, socket) do
    prompt_params = maybe_generate_slug(prompt_params)

    changeset =
      %Prompts.Prompt{}
      |> Prompts.change_prompt(prompt_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"prompt" => prompt_params}, socket) do
    project = socket.assigns.project
    project_id_str = if project, do: Integer.to_string(project.id), else: nil

    prompt_params =
      if project_id_str,
        do: Map.put(prompt_params, "project_id", project_id_str),
        else: prompt_params

    case Prompts.create_prompt(prompt_params) do
      {:ok, prompt} ->
        return_to =
          if project,
            do: ~p"/projects/#{project.id}/prompts/#{prompt.uuid}",
            else: ~p"/"

        {:noreply,
         socket
         |> put_flash(:info, "Prompt created successfully")
         |> push_navigate(to: return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp maybe_generate_slug(%{"name" => name, "slug" => ""} = params) when byte_size(name) > 0 do
    slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    Map.put(params, "slug", slug)
  end

  defp maybe_generate_slug(params), do: params

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <div class="mb-6">
        <%= if @project do %>
          <.link navigate={~p"/projects/#{@project.id}/prompts"} class="btn btn-ghost btn-sm gap-2">
            <.icon name="hero-arrow-left" class="size-4" /> Back to Prompts
          </.link>
        <% end %>
      </div>

      <div class="sm:flex sm:items-center mb-6">
        <div class="sm:flex-auto">
          <h1 class="text-2xl font-semibold leading-6 text-base-content">
            New Prompt
          </h1>
          <p class="mt-2 text-sm text-base-content/70">
            Create a reusable prompt template for subagents
            <%= if @project do %>
              in <span class="font-medium">{@project.name}</span>
            <% end %>
          </p>
        </div>
      </div>

      <.form
        for={@form}
        phx-change="validate"
        phx-submit="save"
        class="card bg-base-100 shadow-xl max-w-3xl"
      >
        <div class="card-body gap-4">
          <div class="form-control">
            <label class="label">
              <span class="label-text font-semibold">Name <span class="text-error">*</span></span>
            </label>
            <.input field={@form[:name]} type="text" placeholder="My Skill Name" phx-debounce="300" />
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-semibold">Slug <span class="text-error">*</span></span>
              <span class="label-text-alt text-base-content/30">Auto-generated from name</span>
            </label>
            <.input
              field={@form[:slug]}
              type="text"
              placeholder="my-skill-name"
              class="font-mono"
              phx-debounce="300"
            />
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-semibold">Description</span>
            </label>
            <.input
              field={@form[:description]}
              type="text"
              placeholder="What this prompt does and when to use it"
              phx-debounce="300"
            />
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-semibold">
                Prompt Text <span class="text-error">*</span>
              </span>
            </label>
            <.input
              field={@form[:prompt_text]}
              type="textarea"
              rows="20"
              class="font-mono text-sm"
              placeholder="Write the prompt instructions here..."
              phx-debounce="blur"
            />
          </div>

          <div class="card-actions justify-end mt-2">
            <%= if @project do %>
              <.link navigate={~p"/projects/#{@project.id}/prompts"} class="btn btn-ghost">
                Cancel
              </.link>
            <% end %>
            <button type="submit" class="btn btn-primary">
              <.icon name="hero-check" class="size-4" /> Create Prompt
            </button>
          </div>
        </div>
      </.form>
    </div>
    """
  end
end
