defmodule EyeInTheSkyWeb.IAMLive.PolicyEdit do
  @moduledoc """
  Edit form for an existing IAM policy.

  Backed by `Policy.update_changeset/2`. For system policies (those carrying a
  non-nil `system_key`), only fields listed in the row's `editable_fields`
  whitelist are writable — every other input is rendered `disabled` and the
  server-side `enforce_locked_fields` guard in the changeset catches any
  attempt to mutate locked fields anyway.

  The UI exposes a Scope radio — Global / Project / Path glob — that drives
  which of `project_id`/`project_path` is shown. Initial scope is inferred
  from the existing policy values.
  """
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.Policy
  alias EyeInTheSky.Projects
  alias EyeInTheSky.Utils.ToolHelpers

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case ToolHelpers.parse_int(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid policy ID.")
         |> push_navigate(to: ~p"/iam/policies")}

      int_id ->
        case IAM.get_policy(int_id) do
          {:ok, %Policy{} = policy} ->
            changeset = Policy.update_changeset(policy, %{})

            {:ok,
             socket
             |> assign(:page_title, "Edit: #{policy.name}")
             |> assign(:sidebar_tab, :iam)
             |> assign(:sidebar_project, nil)
             |> assign(:policy, policy)
             |> assign(:system?, not is_nil(policy.system_key))
             |> assign(:editable_fields, MapSet.new(policy.editable_fields || []))
             |> assign(:form, to_form(changeset))
             |> assign(:condition_text, encode_condition(policy.condition))
             |> assign(:scope, infer_scope(policy))
             |> assign(:projects, Projects.list_projects())}

          {:error, :not_found} ->
            {:ok,
             socket
             |> put_flash(:error, "Policy not found.")
             |> push_navigate(to: ~p"/iam/policies")}
        end
    end
  end

  @impl true
  def handle_event("validate", %{"policy" => raw_params} = event_params, socket) do
    condition_text = Map.get(event_params, "condition_text", socket.assigns.condition_text)
    scope = Map.get(event_params, "scope", socket.assigns.scope)
    params = raw_params |> apply_scope(scope) |> scrub_empty()
    {attrs, condition_error} = merge_condition(params, condition_text)

    changeset =
      socket.assigns.policy
      |> Policy.update_changeset(attrs)
      |> apply_condition_error(condition_error)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:condition_text, condition_text)
     |> assign(:scope, scope)}
  end

  def handle_event("save", %{"policy" => raw_params} = event_params, socket) do
    condition_text = Map.get(event_params, "condition_text", socket.assigns.condition_text)
    scope = Map.get(event_params, "scope", socket.assigns.scope)
    params = raw_params |> apply_scope(scope) |> scrub_empty()

    case merge_condition(params, condition_text) do
      {attrs, nil} ->
        case IAM.update_policy(socket.assigns.policy, attrs) do
          {:ok, _policy} ->
            {:noreply,
             socket
             |> put_flash(:info, "Policy updated.")
             |> push_navigate(to: ~p"/iam/policies")}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply,
             socket
             |> assign(:form, to_form(Map.put(cs, :action, :update)))
             |> assign(:condition_text, condition_text)
             |> assign(:scope, scope)}
        end

      {_attrs, error} ->
        cs =
          socket.assigns.policy
          |> Policy.update_changeset(Map.put(params, "condition", %{}))
          |> apply_condition_error(error)
          |> Map.put(:action, :update)

        {:noreply,
         socket
         |> assign(:form, to_form(cs))
         |> assign(:condition_text, condition_text)
         |> assign(:scope, scope)}
    end
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  # Initial scope is inferred from the persisted policy:
  #   project_id set        → :project
  #   project_path != "*"   → :path
  #   otherwise             → :global
  defp infer_scope(%Policy{project_id: pid}) when not is_nil(pid), do: "project"
  defp infer_scope(%Policy{project_path: path}) when path not in [nil, "", "*"], do: "path"
  defp infer_scope(_), do: "global"

  defp apply_scope(params, "global") do
    params
    |> Map.put("project_id", "")
    |> Map.put("project_path", "*")
  end

  defp apply_scope(params, "project") do
    Map.put(params, "project_path", "*")
  end

  defp apply_scope(params, "path") do
    Map.put(params, "project_id", "")
  end

  defp apply_scope(params, _), do: params

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

  @scrub_when_empty ~w(project_id agent_type project_path action resource_glob)

  defp scrub_empty(params) when is_map(params) do
    Enum.reduce(@scrub_when_empty, params, fn key, acc ->
      case Map.get(acc, key) do
        "" -> Map.delete(acc, key)
        _ -> acc
      end
    end)
  end

  defp encode_condition(nil), do: "{}"
  defp encode_condition(%{} = map) when map_size(map) == 0, do: "{}"
  defp encode_condition(%{} = map), do: Jason.encode!(map, pretty: true)

  defp locked?(%{system?: false}, _field), do: false

  defp locked?(%{system?: true, editable_fields: editable}, field) do
    not MapSet.member?(editable, to_string(field))
  end

  defp project_options(projects) do
    [{"-- select a project --", ""} | Enum.map(projects, &{&1.name, &1.id})]
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
        <.icon name="hero-pencil-square" class="w-6 h-6 text-primary" />
        <h1 class="text-2xl font-bold">Edit policy</h1>
        <%= if @system? do %>
          <span class="badge badge-info gap-1">
            <.icon name="hero-lock-closed" class="w-3 h-3" /> system
          </span>
        <% end %>
      </div>

      <%= if @system? do %>
        <div class="alert alert-warning">
          <.icon name="hero-exclamation-triangle" class="w-5 h-5" />
          <div>
            <div class="font-semibold">This is a built-in system policy.</div>
            <div class="text-sm">
              Matcher fields are locked — you can only edit:
              <code class="font-mono">
                <%= Enum.join(@policy.editable_fields || [], ", ") %>
              </code>
            </div>
          </div>
        </div>
      <% end %>

      <.form for={@form} id="iam-policy-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <input type="hidden" name="condition_text" value={@condition_text} />

        <section class="card bg-base-200">
          <div class="card-body p-4 grid grid-cols-1 md:grid-cols-2 gap-4">
            <.input
              field={@form[:name]}
              type="text"
              label="Name"
              required
              disabled={locked?(assigns, :name)}
            />

            <.input
              field={@form[:effect]}
              type="select"
              label="Effect"
              options={[{"allow", "allow"}, {"deny", "deny"}, {"instruct", "instruct"}]}
              required
              disabled={locked?(assigns, :effect)}
            />

            <.input
              field={@form[:agent_type]}
              type="text"
              label="Agent type"
              disabled={locked?(assigns, :agent_type)}
            />

            <.input
              field={@form[:action]}
              type="text"
              label="Action (tool)"
              disabled={locked?(assigns, :action)}
            />

            <.input
              field={@form[:resource_glob]}
              type="text"
              label="Resource glob"
              disabled={locked?(assigns, :resource_glob)}
            />

            <.input
              field={@form[:priority]}
              type="number"
              label="Priority"
              disabled={locked?(assigns, :priority)}
            />

            <.input
              field={@form[:message]}
              type="text"
              label="Message (optional)"
              disabled={locked?(assigns, :message)}
            />

            <.input
              field={@form[:enabled]}
              type="checkbox"
              label="Enabled"
              disabled={locked?(assigns, :enabled)}
            />

            <%= if @system? do %>
              <.input
                field={@form[:builtin_matcher]}
                type="text"
                label="Builtin matcher key"
                disabled={locked?(assigns, :builtin_matcher)}
              />
            <% end %>
          </div>
        </section>

        <section class="card bg-base-200">
          <div class="card-body p-4 space-y-3">
            <div class="flex items-center justify-between">
              <h2 class="font-semibold flex items-center gap-2">
                <.icon name="hero-funnel" class="w-5 h-5" /> Scope
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
                  disabled={locked?(assigns, :project_id) or locked?(assigns, :project_path)}
                />
                <span class="label-text">Global <span class="text-xs opacity-60">— every project</span></span>
              </label>
              <label class="label cursor-pointer gap-2">
                <input
                  type="radio"
                  name="scope"
                  value="project"
                  checked={@scope == "project"}
                  class="radio radio-sm"
                  disabled={locked?(assigns, :project_id) or locked?(assigns, :project_path)}
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
                  disabled={locked?(assigns, :project_id) or locked?(assigns, :project_path)}
                />
                <span class="label-text">Path glob <span class="text-xs opacity-60">— match by filesystem path</span></span>
              </label>
            </div>

            <%= cond do %>
              <% @scope == "project" -> %>
                <.input
                  field={@form[:project_id]}
                  type="select"
                  label="Project"
                  options={project_options(@projects)}
                  disabled={locked?(assigns, :project_id)}
                />
              <% @scope == "path" -> %>
                <.input
                  field={@form[:project_path]}
                  type="text"
                  label="Project path glob"
                  placeholder="/Users/me/projects/*"
                  disabled={locked?(assigns, :project_path)}
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
              disabled={locked?(assigns, :condition)}
            ><%= @condition_text %></textarea>

            <%= if cond_error = @form[:condition].errors |> List.first() do %>
              <p class="text-error text-xs"><%= elem(cond_error, 0) %></p>
            <% end %>
          </div>
        </section>

        <div class="flex justify-end gap-2">
          <.link navigate={~p"/iam/policies"} class="btn btn-ghost">Cancel</.link>
          <button type="submit" class="btn btn-primary">
            <.icon name="hero-check" class="w-4 h-4" /> Save changes
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
