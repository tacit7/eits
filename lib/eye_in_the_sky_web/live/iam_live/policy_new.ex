defmodule EyeInTheSkyWeb.IAMLive.PolicyNew do
  @moduledoc """
  Create form for a user IAM policy.

  Backed by `Policy.create_changeset/2`. The `condition` field accepts JSON
  text — we decode on submit and surface JSON-parse failures as a changeset
  error before hitting `IAM.create_policy/1`.

  System policies are seeded via migrations (not this form) — `system_key`,
  `editable_fields`, and `builtin_matcher` are deliberately omitted here.
  """
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.Policy

  @impl true
  def mount(_params, _session, socket) do
    changeset = Policy.create_changeset(%Policy{priority: 0, enabled: true}, %{})

    {:ok,
     socket
     |> assign(:page_title, "New IAM Policy")
     |> assign(:sidebar_tab, :iam)
     |> assign(:sidebar_project, nil)
     |> assign(:form, to_form(changeset))
     |> assign(:condition_text, "{}")}
  end

  @impl true
  def handle_event("validate", %{"policy" => raw_params} = event_params, socket) do
    condition_text = Map.get(event_params, "condition_text", "{}")
    params = scrub_empty(raw_params)
    {attrs, condition_error} = merge_condition(params, condition_text)

    changeset =
      %Policy{}
      |> Policy.create_changeset(attrs)
      |> apply_condition_error(condition_error)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:condition_text, condition_text)}
  end

  def handle_event("save", %{"policy" => raw_params} = event_params, socket) do
    condition_text = Map.get(event_params, "condition_text", "{}")
    params = scrub_empty(raw_params)

    case merge_condition(params, condition_text) do
      {attrs, nil} ->
        case IAM.create_policy(attrs) do
          {:ok, _policy} ->
            {:noreply,
             socket
             |> put_flash(:info, "Policy created.")
             |> push_navigate(to: ~p"/iam/policies")}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply,
             socket
             |> assign(:form, to_form(Map.put(cs, :action, :insert)))
             |> assign(:condition_text, condition_text)}
        end

      {_attrs, error} ->
        cs =
          %Policy{}
          |> Policy.create_changeset(Map.put(params, "condition", %{}))
          |> apply_condition_error(error)
          |> Map.put(:action, :insert)

        {:noreply,
         socket
         |> assign(:form, to_form(cs))
         |> assign(:condition_text, condition_text)}
    end
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp merge_condition(params, condition_text) do
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
            {Map.put(params, "condition", %{}),
             "invalid JSON: #{Exception.message(err)}"}
        end
    end
  end

  defp apply_condition_error(changeset, nil), do: changeset

  defp apply_condition_error(changeset, message) do
    Ecto.Changeset.add_error(changeset, :condition, message)
  end

  # Only a subset of fields need empty-string scrubbing:
  #   * `:id`-cast fields fail on "" (project_id)
  #   * fields with a non-nil schema default (agent_type, project_path, action)
  #     should drop to let the default win when left blank
  #   * `resource_glob` is optional; empty string triggers a "must not be
  #     empty" error from `validate_glob_or_wildcard`
  #
  # Required string fields (`name`, `effect`) are intentionally preserved so
  # `validate_required` surfaces a `"can't be blank"` error in the form.
  @scrub_when_empty ~w(project_id agent_type project_path action resource_glob)

  defp scrub_empty(params) when is_map(params) do
    Enum.reduce(@scrub_when_empty, params, fn key, acc ->
      case Map.get(acc, key) do
        "" -> Map.delete(acc, key)
        _ -> acc
      end
    end)
  end

  # ── rendering ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-4xl mx-auto space-y-6">
      <div class="flex items-center gap-3">
        <.link navigate={~p"/iam/policies"} class="btn btn-ghost btn-sm">
          <.icon name="hero-arrow-left" class="w-4 h-4" />
        </.link>
        <.icon name="hero-shield-plus" class="w-6 h-6 text-primary" />
        <h1 class="text-2xl font-bold">New IAM Policy</h1>
      </div>

      <.form for={@form} id="iam-policy-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <input type="hidden" name="condition_text" value={@condition_text} />

        <section class="card bg-base-200">
          <div class="card-body p-4 grid grid-cols-1 md:grid-cols-2 gap-4">
            <.input field={@form[:name]} type="text" label="Name" placeholder="Block writes to /etc" required />

            <.input
              field={@form[:effect]}
              type="select"
              label="Effect"
              options={[{"allow", "allow"}, {"deny", "deny"}, {"instruct", "instruct"}]}
              required
            />

            <.input field={@form[:agent_type]} type="text" label="Agent type" placeholder="* or e.g. root" />

            <.input field={@form[:action]} type="text" label="Action (tool)" placeholder="* or e.g. Bash" />

            <.input field={@form[:project_id]} type="number" label="Project ID (optional)" placeholder="integer" />

            <.input field={@form[:project_path]} type="text" label="Project path glob" placeholder="* or /Users/me/projects/*" />

            <.input field={@form[:resource_glob]} type="text" label="Resource glob" placeholder="e.g. /etc/*" />

            <.input field={@form[:priority]} type="number" label="Priority" />

            <.input field={@form[:message]} type="text" label="Message (optional)" placeholder="Shown when this policy wins" />

            <.input field={@form[:enabled]} type="checkbox" label="Enabled" />
          </div>
        </section>

        <section class="card bg-base-200">
          <div class="card-body p-4 space-y-2">
            <div class="flex items-center justify-between">
              <h2 class="font-semibold flex items-center gap-2">
                <.icon name="hero-code-bracket" class="w-5 h-5" /> Condition (JSON)
              </h2>
              <span class="text-xs text-base-content/60">
                Predicates: time_between, env_equals, session_state_equals
              </span>
            </div>

            <textarea
              name="condition_text"
              rows="6"
              class="textarea textarea-bordered textarea-sm font-mono text-xs w-full"
              placeholder='{"time_between": ["09:00", "17:00"]}'
            ><%= @condition_text %></textarea>

            <%= if cond_error = @form[:condition].errors |> List.first() do %>
              <p class="text-error text-xs"><%= elem(cond_error, 0) %></p>
            <% end %>
          </div>
        </section>

        <div class="flex justify-end gap-2">
          <.link navigate={~p"/iam/policies"} class="btn btn-ghost">Cancel</.link>
          <button type="submit" class="btn btn-primary">
            <.icon name="hero-check" class="w-4 h-4" /> Create policy
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
