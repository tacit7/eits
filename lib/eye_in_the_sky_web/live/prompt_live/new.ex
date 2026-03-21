defmodule EyeInTheSkyWeb.PromptLive.New do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Prompts

  @impl true
  def mount(_params, _session, socket) do
    changeset = Prompts.change_prompt(%Prompts.Prompt{})

    socket =
      socket
      |> assign(:page_title, "New Prompt")
      |> assign(:form, to_form(changeset))
      |> assign(:sidebar_tab, :prompts)
      |> assign(:sidebar_project, nil)

    {:ok, socket}
  end

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
    case Prompts.create_prompt(prompt_params) do
      {:ok, prompt} ->
        {:noreply,
         socket
         |> put_flash(:info, "Prompt created successfully")
         |> push_navigate(to: ~p"/prompts/#{prompt.uuid}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # Auto-generate slug from name if slug is empty
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
        <.link navigate={~p"/prompts"} class="btn btn-ghost btn-sm gap-2">
          <.icon name="hero-arrow-left" class="h-4 w-4" /> Back to Prompts
        </.link>
      </div>

      <div class="sm:flex sm:items-center mb-6">
        <div class="sm:flex-auto">
          <h1 class="text-2xl font-semibold leading-6 text-gray-900 dark:text-gray-100">
            New Prompt
          </h1>
          <p class="mt-2 text-sm text-gray-700 dark:text-gray-400">
            Create a reusable prompt template for subagents
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
              <span class="label-text-alt text-gray-400">Auto-generated from name</span>
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
            <.link navigate={~p"/prompts"} class="btn btn-ghost">
              Cancel
            </.link>
            <button type="submit" class="btn btn-primary">
              <.icon name="hero-check" class="h-4 w-4" /> Create Prompt
            </button>
          </div>
        </div>
      </.form>
    </div>
    """
  end
end
