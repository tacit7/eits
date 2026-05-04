defmodule EyeInTheSkyWeb.IAMLive.PolicyNew do
  @moduledoc """
  Create form for a user IAM policy.

  Backed by `Policy.create_changeset/2`. The `condition` field accepts JSON
  text — we decode on submit and surface JSON-parse failures as a changeset
  error before hitting `IAM.create_policy/1`.

  The UI exposes a three-option **Scope** radio — Global / Project / Path
  glob — that drives which of `project_id`/`project_path` the operator sees.
  The underlying schema is unchanged: Global clears both, Project sets
  `project_id`, Path glob sets `project_path`.

  System policies are seeded via migrations (not this form) — `system_key`,
  `editable_fields`, and `builtin_matcher` are deliberately omitted here.
  """
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.IAMLive.IAMComponents
  import EyeInTheSkyWeb.IAMLive.PolicyFormHelpers

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.HooksChecker
  alias EyeInTheSky.IAM.Policy
  alias EyeInTheSky.Projects

  @impl true
  def mount(_params, _session, socket) do
    changeset = Policy.create_changeset(%Policy{priority: 0, enabled: true}, %{})
    projects = if connected?(socket), do: Projects.list_projects(), else: []

    {:ok,
     socket
     |> assign(:page_title, "New IAM Policy")
     |> assign(:sidebar_tab, :iam)
     |> assign(:sidebar_project, nil)
     |> assign(:form, to_form(changeset))
     |> assign(:condition_text, "{}")
     |> assign(:scope, "global")
     |> assign(:projects, projects)
     |> assign(:iam_hooks_status, HooksChecker.status())}
  end

  @impl true
  def handle_event("validate", %{"policy" => raw_params} = event_params, socket) do
    condition_text = Map.get(event_params, "condition_text", "{}")
    scope = Map.get(event_params, "scope", socket.assigns.scope)
    params = raw_params |> apply_scope(scope) |> scrub_empty()
    {attrs, condition_error} = merge_condition(params, condition_text)

    changeset =
      %Policy{}
      |> Policy.create_changeset(attrs)
      |> apply_condition_error(condition_error)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:condition_text, condition_text)
     |> assign(:scope, scope)}
  end

  def handle_event("save", %{"policy" => raw_params} = event_params, socket) do
    condition_text = Map.get(event_params, "condition_text", "{}")
    scope = Map.get(event_params, "scope", socket.assigns.scope)
    params = raw_params |> apply_scope(scope) |> scrub_empty()

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
             |> assign(:condition_text, condition_text)
             |> assign(:scope, scope)}
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
         |> assign(:condition_text, condition_text)
         |> assign(:scope, scope)}
    end
  end

  # ── rendering ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-4xl mx-auto space-y-6">
      <.iam_offline_banner hooks_status={@iam_hooks_status} />
      <div class="flex items-center gap-3">
        <.link navigate={~p"/iam/policies"} class="btn btn-ghost btn-sm">
          <.icon name="hero-arrow-left" class="size-4" />
        </.link>
        <.icon name="hero-shield-plus" class="size-6 text-primary" />
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

            <.input field={@form[:resource_glob]} type="text" label="Resource glob" placeholder="e.g. /etc/*" />

            <.input field={@form[:priority]} type="number" label="Priority" />

            <.input field={@form[:message]} type="text" label="Message (optional)" placeholder="Shown when this policy wins" />

            <.input field={@form[:enabled]} type="checkbox" label="Enabled" />
          </div>
        </section>

        <.policy_form_fields
          form={@form}
          scope={@scope}
          projects={@projects}
          condition_text={@condition_text}
        />

        <div class="flex justify-end gap-2">
          <.form_actions submit_text="Create policy" cancel_navigate={~p"/iam/policies"} />
        </div>
      </.form>
    </div>
    """
  end
end
