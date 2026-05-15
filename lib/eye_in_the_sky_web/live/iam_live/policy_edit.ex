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

  import EyeInTheSkyWeb.IAMLive.IAMComponents
  import EyeInTheSkyWeb.IAMLive.PolicyFormHelpers

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.HooksChecker
  alias EyeInTheSky.IAM.Policy
  alias EyeInTheSky.Projects
  alias EyeInTheSky.Utils.ToolHelpers
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case ToolHelpers.parse_int(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid policy ID.")
         |> push_navigate(to: ~p"/iam/policies")}

      int_id ->
        if connected?(socket) do
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
               |> assign(:projects, Projects.list_projects())
               |> assign(:matcher_source, load_matcher_source(policy.builtin_matcher))
               |> assign(:iam_hooks_status, HooksChecker.status())}

            {:error, :not_found} ->
              {:ok,
               socket
               |> put_flash(:error, "Policy not found.")
               |> push_navigate(to: ~p"/iam/policies")}
          end
        else
          blank = %Policy{}
          changeset = Policy.update_changeset(blank, %{})

          {:ok,
           socket
           |> assign(:page_title, "Edit policy")
           |> assign(:sidebar_tab, :iam)
           |> assign(:sidebar_project, nil)
           |> assign(:policy, blank)
           |> assign(:system?, false)
           |> assign(:editable_fields, MapSet.new([]))
           |> assign(:form, to_form(changeset))
           |> assign(:condition_text, "{}")
           |> assign(:scope, "global")
           |> assign(:projects, [])
           |> assign(:matcher_source, nil)
           |> assign(:iam_hooks_status, HooksChecker.status())}
        end
    end
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

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

  @impl true
  def handle_event("reseed", _params, socket) do
    policy = socket.assigns.policy

    case IAM.reseed_builtin(policy.system_key) do
      {:ok, updated} ->
        changeset = Policy.update_changeset(updated, %{})

        {:noreply,
         socket
         |> assign(:policy, updated)
         |> assign(:form, to_form(changeset))
         |> assign(:condition_text, encode_condition(updated.condition))
         |> assign(:scope, infer_scope(updated))
         |> put_flash(:info, "Policy reset to seed defaults.")}

      {:error, :not_in_seeds} ->
        {:noreply, put_flash(socket, :error, "No seed definition found for this policy.")}

      {:error, _cs} ->
        {:noreply, put_flash(socket, :error, "Failed to reseed policy.")}
    end
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

  defp encode_condition(nil), do: "{}"
  defp encode_condition(%{} = map) when map_size(map) == 0, do: "{}"
  defp encode_condition(%{} = map), do: Jason.encode!(map, pretty: true)

  defp locked?(%{system?: false}, _field), do: false

  defp locked?(%{system?: true, editable_fields: editable}, field) do
    not MapSet.member?(editable, to_string(field))
  end

  defp load_matcher_source(nil), do: nil

  defp load_matcher_source(key) when is_binary(key) do
    with {:ok, module} <- EyeInTheSky.IAM.BuiltinMatcher.Registry.fetch(key),
         source_path when is_list(source_path) <- module.__info__(:compile)[:source],
         path = List.to_string(source_path),
         {:ok, content} <- File.read(path) do
      content
    else
      _ -> nil
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
        <.icon name="hero-pencil-square" class="size-6 text-primary" />
        <h1 class="text-2xl font-bold">Edit policy</h1>
        <%= if @system? do %>
          <span class="badge badge-info gap-1">
            <.icon name="hero-lock-closed" class="size-3" /> system
          </span>
        <% end %>
      </div>

      <%= if @system? do %>
        <div class="alert alert-warning">
          <.icon name="hero-exclamation-triangle" class="size-5" />
          <div>
            <div class="font-semibold">This is a built-in system policy.</div>
            <div class="text-sm">
              Matcher fields are locked — you can only edit:
              <code class="font-mono">
                {Enum.join(@policy.editable_fields || [], ", ")}
              </code>
            </div>
          </div>
        </div>
      <% end %>

      <.form
        for={@form}
        id="iam-policy-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
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

        <.policy_form_fields
          form={@form}
          scope={@scope}
          projects={@projects}
          condition_text={@condition_text}
          scope_disabled={locked?(assigns, :project_id) or locked?(assigns, :project_path)}
          project_id_disabled={locked?(assigns, :project_id)}
          project_path_disabled={locked?(assigns, :project_path)}
          condition_disabled={locked?(assigns, :condition)}
        />

        <div class="flex justify-between gap-2">
          <%= if @system? do %>
            <button
              type="button"
              class="btn btn-ghost btn-sm text-warning"
              phx-click="reseed"
              data-confirm="Reset this policy to its seed defaults? All customizations (enabled, priority, condition, message) will be overwritten."
            >
              <.icon name="hero-arrow-path" class="size-4" /> Reset to seed defaults
            </button>
          <% else %>
            <div />
          <% end %>
          <.form_actions submit_text="Save changes" cancel_navigate={~p"/iam/policies"} />
        </div>
      </.form>

      <%= if @matcher_source do %>
        <details class="collapse collapse-arrow bg-base-200">
          <summary class="collapse-title font-semibold flex items-center gap-2 min-h-0 py-3 px-4">
            <.icon name="hero-code-bracket" class="size-4 text-primary" />
            Matcher source
            <code class="font-mono text-xs text-base-content/60 ml-1">
              {@policy.builtin_matcher}.ex
            </code>
          </summary>
          <div class="collapse-content px-0 pb-0">
            <pre class="overflow-x-auto text-xs font-mono leading-relaxed p-4 bg-base-300 rounded-b-box max-h-[32rem] overflow-y-auto"><code>{@matcher_source}</code></pre>
          </div>
        </details>
      <% end %>
    </div>
    """
  end
end
