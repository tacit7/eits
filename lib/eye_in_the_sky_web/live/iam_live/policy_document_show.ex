defmodule EyeInTheSkyWeb.IAMLive.PolicyDocumentShow do
  @moduledoc """
  Show page for an IAM policy document.

  Manages policy membership (add/remove), agent type attachments
  (attach/detach), and displays conflict heuristics for overlapping
  allow/deny policies.
  """
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.IAMLive.IAMComponents

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.HooksChecker
  alias EyeInTheSky.IAM.PolicyDocument
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {int_id, ""} ->
        if connected?(socket) do
          load_document(int_id, socket)
        else
          {:ok,
           socket
           |> assign(:page_title, "Policy Document")
           |> assign(:sidebar_tab, :iam)
           |> assign(:sidebar_project, nil)
           |> assign(:document, nil)
           |> assign(:all_policies, [])
           |> assign(:add_policy_id, "")
           |> assign(:new_agent_type, "")
           |> assign(:iam_hooks_status, HooksChecker.status())}
        end

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid document ID.")
         |> push_navigate(to: ~p"/iam/documents")}
    end
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  @impl true
  def handle_event("add_policy", %{"policy_id" => policy_id_str}, socket) do
    doc = socket.assigns.document

    case Integer.parse(policy_id_str) do
      {policy_id, ""} ->
        case IAM.add_policy_to_document(doc.id, policy_id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Policy added to document.")
             |> reload_document()}

          {:error, :already_attached} ->
            {:noreply, put_flash(socket, :error, "Policy is already in this document.")}

          {:error, :policy_not_found} ->
            {:noreply, put_flash(socket, :error, "Policy not found.")}

          {:error, :document_not_found} ->
            {:noreply, put_flash(socket, :error, "Document not found.")}

          {:error, _cs} ->
            {:noreply, put_flash(socket, :error, "Failed to add policy.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Select a policy to add.")}
    end
  end

  @impl true
  def handle_event("remove_policy", %{"policy_id" => policy_id_str}, socket) do
    doc = socket.assigns.document

    case Integer.parse(policy_id_str) do
      {policy_id, ""} ->
        case IAM.remove_policy_from_document(doc.id, policy_id) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "Policy removed from document.")
             |> reload_document()}

          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Policy not found in document.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid policy ID.")}
    end
  end

  @impl true
  def handle_event("attach_agent_type", %{"agent_type" => agent_type}, socket) do
    agent_type = String.trim(agent_type)
    doc = socket.assigns.document

    cond do
      agent_type == "" ->
        {:noreply, put_flash(socket, :error, "Agent type cannot be blank.")}

      agent_type == "*" ->
        {:noreply, put_flash(socket, :error, "Wildcard \"*\" cannot be used as an agent type.")}

      true ->
        case IAM.attach_document_to_agent_type(agent_type, doc.id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Document attached to agent type \"#{agent_type}\".")
             |> assign(:new_agent_type, "")
             |> reload_document()}

          {:error, :already_attached} ->
            {:noreply,
             put_flash(socket, :error, "Document already attached to \"#{agent_type}\".")}

          {:error, :document_not_found} ->
            {:noreply, put_flash(socket, :error, "Document not found.")}

          {:error, _cs} ->
            {:noreply, put_flash(socket, :error, "Failed to attach agent type.")}
        end
    end
  end

  @impl true
  def handle_event("detach_agent_type", %{"agent_type" => agent_type}, socket) do
    doc = socket.assigns.document

    case IAM.detach_document_from_agent_type(agent_type, doc.id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Agent type \"#{agent_type}\" detached.")
         |> reload_document()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Agent type attachment not found.")}
    end
  end

  @impl true
  def handle_event("delete_document", _params, socket) do
    doc = socket.assigns.document

    case IAM.delete_policy_document(doc) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Document \"#{doc.name}\" deleted.")
         |> push_navigate(to: ~p"/iam/documents")}

      {:error, _cs} ->
        {:noreply, put_flash(socket, :error, "Failed to delete document.")}
    end
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp load_document(id, socket) do
    case IAM.get_policy_document(id,
           preload: [document_policies: [:policy], agent_type_documents: []]
         ) do
      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Document not found.")
         |> push_navigate(to: ~p"/iam/documents")}

      {:ok, %PolicyDocument{} = doc} ->
        all_policies = IAM.list_policies()

        {:ok,
         socket
         |> assign(:page_title, doc.name)
         |> assign(:sidebar_tab, :iam)
         |> assign(:sidebar_project, nil)
         |> assign(:document, doc)
         |> assign(:all_policies, all_policies)
         |> assign(:add_policy_id, "")
         |> assign(:new_agent_type, "")
         |> assign(:iam_hooks_status, HooksChecker.status())}
    end
  end

  defp reload_document(socket) do
    doc = socket.assigns.document

    case IAM.get_policy_document(doc.id,
           preload: [document_policies: [:policy], agent_type_documents: []]
         ) do
      {:ok, updated_doc} ->
        assign(socket, :document, updated_doc)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Document was deleted.")
        |> push_navigate(to: ~p"/iam/documents")
    end
  end

  defp attached_count(doc), do: length(doc.document_policies)

  defp conflict_detected?(doc) do
    enabled_policies = doc.document_policies

    allows = Enum.filter(enabled_policies, &(&1.policy.effect == "allow"))
    denies = Enum.filter(enabled_policies, &(&1.policy.effect == "deny"))

    allows != [] and denies != [] and
      Enum.any?(allows, fn allow ->
        Enum.any?(denies, fn deny ->
          actions_overlap?(allow.policy.action, deny.policy.action)
        end)
      end)
  end

  defp actions_overlap?(a, b) do
    a == "*" or b == "*" or a == b
  end

  defp simulator_path(doc) do
    case doc.agent_type_documents do
      [atd | _] -> ~p"/iam/simulator?agent_type=#{atd.agent_type}"
      [] -> ~p"/iam/simulator"
    end
  end

  defp delete_confirm_text(doc) do
    n = length(doc.agent_type_documents)
    "Deleting this document removes it from #{n} agent type(s). The underlying policies are not deleted."
  end

  # ── rendering ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto space-y-6">
      <.iam_offline_banner hooks_status={@iam_hooks_status} />

      <%= if @document do %>
        <%!-- Header --%>
        <div class="flex items-center justify-between gap-3 flex-wrap">
          <div class="flex items-center gap-3">
            <.link navigate={~p"/iam/documents"} class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-left" class="size-4" />
            </.link>
            <.icon name="hero-document-text" class="size-6 text-primary" />
            <h1 class="text-2xl font-bold">{@document.name}</h1>
          </div>

          <div class="flex items-center gap-2">
            <.link navigate={simulator_path(@document)} class="btn btn-ghost btn-sm">
              <.icon name="hero-beaker" class="size-4" /> Test in simulator
            </.link>
            <.link navigate={~p"/iam/documents/#{@document.id}/edit"} class="btn btn-ghost btn-sm">
              <.icon name="hero-pencil-square" class="size-4" /> Edit
            </.link>
            <button
              type="button"
              class="btn btn-ghost btn-sm text-error"
              phx-click="delete_document"
              data-confirm={delete_confirm_text(@document)}
            >
              <.icon name="hero-trash" class="size-4" /> Delete
            </button>
          </div>
        </div>

        <%= if @document.description do %>
          <p class="text-base-content/70">{@document.description}</p>
        <% end %>

        <%!-- Agent-type bypass note --%>
        <div class="alert alert-info">
          <.icon name="hero-information-circle" class="size-5 shrink-0" />
          <span>
            When policies run from a document, the policy-level agent type is bypassed.
            The document attachment controls which agent type these policies apply to.
          </span>
        </div>

        <%!-- Conflict notice --%>
        <%= if conflict_detected?(@document) do %>
          <div class="alert alert-warning">
            <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
            <span>
              This document contains both allow and deny policies that may overlap.
              Deny rules take precedence. Use the simulator to verify exact behavior.
            </span>
          </div>
        <% end %>

        <%!-- Policies section --%>
        <section class="card bg-base-200">
          <div class="card-body p-4 space-y-4">
            <div class="flex items-center justify-between gap-3">
              <h2 class="text-lg font-semibold flex items-center gap-2">
                <.icon name="hero-shield-check" class="size-5" /> Policies in this document
                <span class="badge badge-ghost text-xs font-mono">
                  {attached_count(@document)} policies
                </span>
              </h2>
            </div>

            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Effect</th>
                    <th>Action</th>
                    <th>Agent type — ignored in document</th>
                    <th>Enabled</th>
                    <th class="text-right">Remove</th>
                  </tr>
                </thead>
                <tbody>
                  <%= if @document.document_policies == [] do %>
                    <tr>
                      <td colspan="6" class="text-center py-6 text-base-content/60">
                        No policies attached yet.
                      </td>
                    </tr>
                  <% end %>
                  <%= for dp <- @document.document_policies do %>
                    <tr id={"dp-#{dp.id}"}>
                      <td>
                        <.link
                          navigate={~p"/iam/policies/#{dp.policy.id}/edit"}
                          class="link link-hover font-medium"
                        >
                          {dp.policy.name}
                        </.link>
                      </td>
                      <td>
                        <span class={"badge badge-sm " <> effect_badge(dp.policy.effect)}>
                          {dp.policy.effect}
                        </span>
                      </td>
                      <td class="font-mono text-xs">{dp.policy.action}</td>
                      <td class="font-mono text-xs text-base-content/50">
                        {dp.policy.agent_type}
                      </td>
                      <td>
                        <%= if dp.policy.enabled do %>
                          <.icon name="hero-check-circle" class="size-4 text-success" />
                        <% else %>
                          <span class="text-base-content/40">—</span>
                        <% end %>
                      </td>
                      <td class="text-right">
                        <button
                          type="button"
                          class="btn btn-ghost btn-xs text-error"
                          phx-click="remove_policy"
                          phx-value-policy_id={dp.policy.id}
                          data-confirm={"Remove \"#{dp.policy.name}\" from this document?"}
                        >
                          <.icon name="hero-x-mark" class="size-4" />
                        </button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>

            <%!-- Add policy form --%>
            <form phx-submit="add_policy" class="flex items-end gap-2">
              <div class="form-control flex-1">
                <label class="label">
                  <span class="label-text text-xs">Add policy</span>
                </label>
                <select name="policy_id" class="select select-bordered select-sm">
                  <option value="">Select a policy...</option>
                  <%= for p <- @all_policies do %>
                    <option value={p.id}>{p.name} ({p.effect})</option>
                  <% end %>
                </select>
              </div>
              <button type="submit" class="btn btn-sm btn-primary">
                <.icon name="hero-plus" class="size-4" /> Add
              </button>
            </form>
          </div>
        </section>

        <%!-- Attached agent types section --%>
        <section class="card bg-base-200">
          <div class="card-body p-4 space-y-4">
            <h2 class="text-lg font-semibold flex items-center gap-2">
              <.icon name="hero-cpu-chip" class="size-5" /> Attached agent types
              <span class="badge badge-ghost text-xs">
                {length(@document.agent_type_documents)}
              </span>
            </h2>

            <%= if @document.agent_type_documents == [] do %>
              <p class="text-base-content/60 text-sm">
                No agent types attached. Add one below.
              </p>
            <% else %>
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th>Agent type</th>
                      <th class="text-right">Remove</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for atd <- @document.agent_type_documents do %>
                      <tr id={"atd-#{atd.id}"}>
                        <td>
                          <.link
                            navigate={~p"/iam/agent-types/show?agent_type=#{atd.agent_type}"}
                            class="font-mono text-sm link link-hover"
                          >{atd.agent_type}</.link>
                        </td>
                        <td class="text-right">
                          <button
                            type="button"
                            class="btn btn-ghost btn-xs text-error"
                            phx-click="detach_agent_type"
                            phx-value-agent_type={atd.agent_type}
                            data-confirm={"Detach agent type \"#{atd.agent_type}\" from this document?"}
                          >
                            <.icon name="hero-x-mark" class="size-4" />
                          </button>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>

            <%!-- Attach new agent type --%>
            <form phx-submit="attach_agent_type" class="flex items-end gap-2">
              <div class="form-control flex-1">
                <label class="label">
                  <span class="label-text text-xs">Attach agent type</span>
                </label>
                <input
                  type="text"
                  name="agent_type"
                  value={@new_agent_type}
                  placeholder="e.g. code-reviewer"
                  class="input input-bordered input-sm"
                />
              </div>
              <button type="submit" class="btn btn-sm btn-primary">
                <.icon name="hero-plus" class="size-4" /> Attach
              </button>
            </form>
          </div>
        </section>
      <% else %>
        <div class="text-center py-16 text-base-content/60">Loading...</div>
      <% end %>
    </div>
    """
  end

  defp effect_badge("allow"), do: "badge-success"
  defp effect_badge("deny"), do: "badge-error"
  defp effect_badge("instruct"), do: "badge-warning"
  defp effect_badge(_), do: "badge-ghost"
end
