defmodule EyeInTheSkyWeb.IAMLive.AgentTypes do
  @moduledoc """
  IAM agent type index.

  Lists every agent type that has at least one policy document attached.
  Provides an inline form to attach documents to a new or existing agent type.
  """
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.IAMLive.IAMComponents

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.HooksChecker
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "IAM Agent Types")
      |> assign(:sidebar_tab, :iam)
      |> assign(:sidebar_project, nil)
      |> assign(:iam_hooks_status, HooksChecker.status())
      |> assign(:show_add_form, false)
      |> assign(:add_agent_type, "")
      |> assign(:add_selected_docs, [])

    socket =
      if connected?(socket) do
        socket
        |> assign_agent_types()
        |> assign_available_documents()
      else
        socket
        |> assign(:agent_types, [])
        |> assign(:available_documents, [])
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  def handle_event("toggle_add_form", _params, socket) do
    {:noreply, assign(socket, :show_add_form, not socket.assigns.show_add_form)}
  end

  def handle_event("update_add_form", %{"agent_type" => agent_type}, socket) do
    {:noreply, assign(socket, :add_agent_type, agent_type)}
  end

  def handle_event("toggle_doc_selection", %{"doc_id" => doc_id_str}, socket) do
    doc_id = String.to_integer(doc_id_str)
    current = socket.assigns.add_selected_docs

    updated =
      if doc_id in current do
        List.delete(current, doc_id)
      else
        [doc_id | current]
      end

    {:noreply, assign(socket, :add_selected_docs, updated)}
  end

  def handle_event("attach_documents", _params, socket) do
    agent_type = String.trim(socket.assigns.add_agent_type)
    selected_docs = socket.assigns.add_selected_docs

    cond do
      agent_type == "" ->
        {:noreply, put_flash(socket, :error, "Agent type is required.")}

      selected_docs == [] ->
        {:noreply, put_flash(socket, :error, "Select at least one document.")}

      true ->
        results =
          Enum.map(selected_docs, fn doc_id ->
            IAM.attach_document_to_agent_type(agent_type, doc_id)
          end)

        errors =
          Enum.filter(results, fn
            {:ok, _} -> false
            _ -> true
          end)

        socket =
          if errors == [] do
            socket
            |> put_flash(:info, "Document(s) attached to \"#{agent_type}\".")
            |> assign(:show_add_form, false)
            |> assign(:add_agent_type, "")
            |> assign(:add_selected_docs, [])
            |> assign_agent_types()
          else
            error_msg =
              errors
              |> Enum.map(fn
                {:error, :document_not_found} -> "Document not found"
                {:error, :already_attached} -> "Already attached"
                {:error, _} -> "Attachment failed"
              end)
              |> Enum.join(", ")

            put_flash(socket, :error, "Errors: #{error_msg}")
          end

        {:noreply, socket}
    end
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp assign_agent_types(socket) do
    assign(socket, :agent_types, IAM.list_agent_types_with_documents())
  end

  defp assign_available_documents(socket) do
    assign(socket, :available_documents, IAM.list_policy_documents())
  end

  # ── rendering ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto space-y-6">
      <.iam_offline_banner hooks_status={@iam_hooks_status} />

      <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-3">
          <.icon name="hero-users" class="size-6 text-primary" />
          <h1 class="text-2xl font-bold">Agent Types</h1>
          <span class="badge badge-ghost">{length(@agent_types)}</span>
        </div>

        <button
          type="button"
          class="btn btn-primary btn-sm"
          phx-click="toggle_add_form"
        >
          <.icon name="hero-plus" class="size-4" />
          {if @show_add_form, do: "Cancel", else: "Add agent type"}
        </button>
      </div>

      <%= if @show_add_form do %>
        <section class="card bg-base-200">
          <div class="card-body p-4 space-y-4">
            <h2 class="card-title text-base">Attach documents to agent type</h2>

            <div class="space-y-3">
              <label class="form-control">
                <span class="label-text text-xs">Agent type</span>
                <input
                  type="text"
                  placeholder="e.g. code-reviewer"
                  value={@add_agent_type}
                  phx-change="update_add_form"
                  name="agent_type"
                  class="input input-bordered input-sm font-mono"
                />
              </label>

              <div>
                <span class="label-text text-xs">Documents</span>
                <div class="mt-1 space-y-1 max-h-48 overflow-y-auto border border-base-content/10 rounded p-2">
                  <%= if @available_documents == [] do %>
                    <p class="text-xs text-base-content/50 py-2 text-center">No documents available</p>
                  <% end %>
                  <%= for doc <- @available_documents do %>
                    <label class="flex items-center gap-2 cursor-pointer py-1 px-1 hover:bg-base-content/5 rounded">
                      <input
                        type="checkbox"
                        class="checkbox checkbox-sm"
                        checked={doc.id in @add_selected_docs}
                        phx-click="toggle_doc_selection"
                        phx-value-doc_id={doc.id}
                      />
                      <span class="text-sm font-medium">{doc.name}</span>
                      <%= if doc.description do %>
                        <span class="text-xs text-base-content/50 truncate">{doc.description}</span>
                      <% end %>
                    </label>
                  <% end %>
                </div>
              </div>

              <button
                type="button"
                class="btn btn-primary btn-sm"
                phx-click="attach_documents"
              >
                Attach
              </button>
            </div>
          </div>
        </section>
      <% end %>

      <section class="card bg-base-200">
        <div class="card-body p-0">
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Agent type</th>
                  <th>Attached documents</th>
                  <th>Documents</th>
                </tr>
              </thead>
              <tbody>
                <%= if @agent_types == [] do %>
                  <tr>
                    <td colspan="3" class="text-center py-8 text-base-content/60">
                      No agent types have documents attached yet.
                    </td>
                  </tr>
                <% end %>
                <%= for {agent_type, docs} <- @agent_types do %>
                  <tr id={"agent-type-#{agent_type}"}>
                    <td>
                      <.link
                        navigate={~p"/iam/agent-types/show?agent_type=#{agent_type}"}
                        class="font-mono font-medium link link-hover"
                      >
                        {agent_type}
                      </.link>
                    </td>
                    <td class="max-w-sm">
                      <div class="flex flex-wrap gap-1">
                        <%= for doc <- docs do %>
                          <span class="badge badge-ghost badge-sm">{doc.name}</span>
                        <% end %>
                      </div>
                    </td>
                    <td class="font-mono text-sm">{length(docs)}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </div>
    """
  end
end
