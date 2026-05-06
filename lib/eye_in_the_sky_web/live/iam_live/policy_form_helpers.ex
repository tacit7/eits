defmodule EyeInTheSkyWeb.IAMLive.PolicyFormHelpers do
  use EyeInTheSkyWeb, :html

  # Fields where an empty string should be dropped so schema defaults win or
  # cast errors are avoided.
  @scrub_when_empty ~w(project_id agent_type project_path action resource_glob)

  def scrub_when_empty, do: @scrub_when_empty

  def apply_scope(params, "global") do
    params
    |> Map.put("project_id", "")
    |> Map.put("project_path", "*")
  end

  def apply_scope(params, "project") do
    Map.put(params, "project_path", "*")
  end

  def apply_scope(params, "path") do
    Map.put(params, "project_id", "")
  end

  def apply_scope(params, _), do: params

  def merge_condition(params, condition_text) do
    trimmed = String.trim(condition_text || "")

    cond do
      trimmed == "" ->
        {Map.put(params, "condition", %{}), nil}

      true ->
        case Jason.decode(trimmed) do
          {:ok, %{} = decoded} ->
            {Map.put(params, "condition", decoded), nil}

          {:ok, _other} ->
            {Map.put(params, "condition", %{}), "must be a JSON object"}

          {:error, %Jason.DecodeError{} = err} ->
            {Map.put(params, "condition", %{}), "invalid JSON: #{Exception.message(err)}"}
        end
    end
  end

  def apply_condition_error(changeset, nil), do: changeset

  def apply_condition_error(changeset, message) do
    Ecto.Changeset.add_error(changeset, :condition, message)
  end

  def scrub_empty(params) when is_map(params) do
    Enum.reduce(@scrub_when_empty, params, fn key, acc ->
      case Map.get(acc, key) do
        "" -> Map.delete(acc, key)
        _ -> acc
      end
    end)
  end

  def project_options(projects) do
    [{"-- select a project --", ""} | Enum.map(projects, &{&1.name, &1.id})]
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :scope, :string, required: true
  attr :projects, :list, required: true
  attr :condition_text, :string, required: true
  attr :scope_disabled, :boolean, default: false
  attr :project_id_disabled, :boolean, default: false
  attr :project_path_disabled, :boolean, default: false
  attr :condition_disabled, :boolean, default: false

  def policy_form_fields(assigns) do
    ~H"""
    <section class="card bg-base-200">
      <div class="card-body p-4 space-y-3">
        <div class="flex items-center justify-between">
          <h2 class="font-semibold flex items-center gap-2">
            <.icon name="hero-funnel" class="size-5" /> Scope
          </h2>
          <span class="text-xs text-base-content/60">
            Controls which hook contexts this policy matches.
          </span>
        </div>

        <div class="flex flex-wrap gap-4">
          <label class="label cursor-pointer gap-2">
            <input
              type="radio"
              name="scope"
              value="global"
              checked={@scope == "global"}
              class="radio radio-sm"
              disabled={@scope_disabled}
            />
            <span class="label-text">
              Global <span class="text-xs opacity-60">— every project</span>
            </span>
          </label>
          <label class="label cursor-pointer gap-2">
            <input
              type="radio"
              name="scope"
              value="project"
              checked={@scope == "project"}
              class="radio radio-sm"
              disabled={@scope_disabled}
            />
            <span class="label-text">Project <span class="text-xs opacity-60">— pick one</span></span>
          </label>
          <label class="label cursor-pointer gap-2">
            <input
              type="radio"
              name="scope"
              value="path"
              checked={@scope == "path"}
              class="radio radio-sm"
              disabled={@scope_disabled}
            />
            <span class="label-text">
              Path glob <span class="text-xs opacity-60">— match by filesystem path</span>
            </span>
          </label>
        </div>

        <%= cond do %>
          <% @scope == "project" -> %>
            <.input
              field={@form[:project_id]}
              type="select"
              label="Project"
              options={project_options(@projects)}
              disabled={@project_id_disabled}
            />
          <% @scope == "path" -> %>
            <.input
              field={@form[:project_path]}
              type="text"
              label="Project path glob"
              placeholder="/Users/me/projects/*"
              disabled={@project_path_disabled}
            />
          <% true -> %>
            <p class="text-xs text-base-content/60">
              This policy will apply to every project.
            </p>
        <% end %>
      </div>
    </section>

    <section class="card bg-base-200">
      <div class="card-body p-4 space-y-2">
        <div class="flex items-center justify-between">
          <h2 class="font-semibold flex items-center gap-2">
            <.icon name="hero-code-bracket" class="size-5" /> Condition (JSON)
          </h2>
          <span class="text-xs text-base-content/60">
            Predicates: time_between, env_equals, session_state_equals
          </span>
        </div>

        <textarea
          name="condition_text"
          rows="6"
          class="textarea textarea-bordered textarea-sm font-mono text-xs w-full"
          disabled={@condition_disabled}
        ><%= @condition_text %></textarea>

        <%= if cond_error = @form[:condition].errors |> List.first() do %>
          <p class="text-error text-xs">{elem(cond_error, 0)}</p>
        <% end %>
      </div>
    </section>
    """
  end
end
