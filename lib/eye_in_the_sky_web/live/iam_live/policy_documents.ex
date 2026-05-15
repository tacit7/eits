defmodule EyeInTheSkyWeb.IAMLive.PolicyDocuments do
  @moduledoc """
  IAM policy document index.

  Lists all policy documents with name, description, attached policy count,
  attached agent types, and action links. Supports delete with cascade warning.
  """
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.IAMLive.IAMComponents

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.HooksChecker
  alias EyeInTheSky.IAM.PolicyDocument
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "IAM Policy Documents")
      |> assign(:sidebar_tab, :iam)
      |> assign(:sidebar_project, nil)
      |> assign(:iam_hooks_status, HooksChecker.status())

    socket =
      if connected?(socket) do
        assign_documents(socket)
      else
        assign(socket, :documents, [])
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {int_id, ""} ->
        case IAM.get_policy_document(int_id, preload: [:agent_type_documents]) do
          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Document not found.")}

          {:ok, %PolicyDocument{} = doc} ->
            agent_type_count = length(doc.agent_type_documents)

            case IAM.delete_policy_document(doc) do
              {:ok, _} ->
                {:noreply,
                 socket
                 |> put_flash(
                   :info,
                   "Document \"#{doc.name}\" deleted. It was removed from #{agent_type_count} agent type(s). The underlying policies are not deleted."
                 )
                 |> assign_documents()}

              {:error, _cs} ->
                {:noreply, put_flash(socket, :error, "Failed to delete document.")}
            end
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid document ID.")}
    end
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp assign_documents(socket) do
    docs =
      IAM.list_policy_documents()
      |> EyeInTheSky.Repo.preload([:agent_type_documents, :document_policies])

    assign(socket, :documents, docs)
  end

  defp agent_types_string([]), do: "—"

  defp agent_types_string(agent_type_docs) do
    agent_type_docs
    |> Enum.map(& &1.agent_type)
    |> Enum.join(", ")
  end

  defp policy_count(doc) do
    length(doc.document_policies)
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
      <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-3">
          <.icon name="hero-document-text" class="size-6 text-primary" />
          <h1 class="text-2xl font-bold">Policy Documents</h1>
          <span class="badge badge-ghost">{length(@documents)}</span>
        </div>

        <.link navigate={~p"/iam/documents/new"} class="btn btn-primary btn-sm">
          <.icon name="hero-plus" class="size-4" /> New document
        </.link>
      </div>

      <section class="card bg-base-200">
        <div class="card-body p-0">
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Description</th>
                  <th>Policies</th>
                  <th>Agent types</th>
                  <th class="text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= if @documents == [] do %>
                  <tr>
                    <td colspan="5" class="text-center py-8 text-base-content/60">
                      No policy documents yet.
                      <.link navigate={~p"/iam/documents/new"} class="link link-primary ml-1">
                        Create one.
                      </.link>
                    </td>
                  </tr>
                <% end %>
                <%= for doc <- @documents do %>
                  <tr id={"document-#{doc.id}"}>
                    <td>
                      <.link
                        navigate={~p"/iam/documents/#{doc.id}"}
                        class="font-medium link link-hover"
                      >
                        {doc.name}
                      </.link>
                    </td>
                    <td class="text-base-content/70 max-w-xs truncate">
                      {doc.description || "—"}
                    </td>
                    <td class="font-mono text-xs">{policy_count(doc)}</td>
                    <td class="text-xs">{agent_types_string(doc.agent_type_documents)}</td>
                    <td class="text-right whitespace-nowrap">
                      <.link
                        navigate={~p"/iam/documents/#{doc.id}"}
                        class="btn btn-ghost btn-xs"
                      >
                        <.icon name="hero-eye" class="size-4" /> Show
                      </.link>
                      <.link
                        navigate={~p"/iam/documents/#{doc.id}/edit"}
                        class="btn btn-ghost btn-xs"
                      >
                        <.icon name="hero-pencil-square" class="size-4" /> Edit
                      </.link>
                      <button
                        type="button"
                        class="btn btn-ghost btn-xs text-error"
                        phx-click="delete"
                        phx-value-id={doc.id}
                        data-confirm={delete_confirm_text(doc)}
                      >
                        <.icon name="hero-trash" class="size-4" />
                      </button>
                    </td>
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
