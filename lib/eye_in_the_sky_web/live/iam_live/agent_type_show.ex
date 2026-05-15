defmodule EyeInTheSkyWeb.IAMLive.AgentTypeShow do
  @moduledoc """
  Detail page for a single IAM agent type.

  Routed via query param: /iam/agent-types/show?agent_type=code-reviewer

  Shows attached documents, allows adding/removing document attachments, and
  displays the count of effective (enabled) policies contributed by all
  attached documents.
  """
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.IAMLive.IAMComponents

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.HooksChecker
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Agent Type")
     |> assign(:sidebar_tab, :iam)
     |> assign(:sidebar_project, nil)
     |> assign(:iam_hooks_status, HooksChecker.status())
     |> assign(:agent_type, nil)
     |> assign(:attached_docs, [])
     |> assign(:effective_policy_count, 0)
     |> assign(:available_documents, [])
     |> assign(:attach_doc_id, nil)}
  end

  @impl true
  def handle_params(%{"agent_type" => agent_type}, _uri, socket) when agent_type != "" do
    socket =
      socket
      |> assign(:agent_type, agent_type)
      |> assign(:page_title, "Agent Type: #{agent_type}")
      |> load_data(agent_type)

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Agent type required.")
     |> push_navigate(to: ~p"/iam/agent-types")}
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  def handle_event("select_attach_doc", %{"doc_id" => doc_id_str}, socket) do
    doc_id =
      case Integer.parse(doc_id_str) do
        {id, ""} -> id
        _ -> nil
      end

    {:noreply, assign(socket, :attach_doc_id, doc_id)}
  end

  def handle_event("attach_document", _params, socket) do
    agent_type = socket.assigns.agent_type
    doc_id = socket.assigns.attach_doc_id

    case doc_id do
      nil ->
        {:noreply, put_flash(socket, :error, "Select a document to attach.")}

      id ->
        case IAM.attach_document_to_agent_type(agent_type, id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Document attached.")
             |> assign(:attach_doc_id, nil)
             |> load_data(agent_type)}

          {:error, :already_attached} ->
            {:noreply, put_flash(socket, :error, "Document is already attached.")}

          {:error, :document_not_found} ->
            {:noreply, put_flash(socket, :error, "Document not found.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to attach document.")}
        end
    end
  end

  def handle_event("detach_document", %{"doc_id" => doc_id_str}, socket) do
    agent_type = socket.assigns.agent_type

    case Integer.parse(doc_id_str) do
      {doc_id, ""} ->
        case IAM.detach_document_from_agent_type(agent_type, doc_id) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "Document detached.")
             |> load_data(agent_type)}

          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Attachment not found.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid document ID.")}
    end
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp load_data(socket, agent_type) do
    all_types = IAM.list_agent_types_with_documents()
    attached_docs = find_docs_for_type(all_types, agent_type)
    effective_policies = IAM.policies_for_agent_type(agent_type)
    all_docs = IAM.list_policy_documents()
    attached_ids = MapSet.new(attached_docs, & &1.id)
    available = Enum.reject(all_docs, &MapSet.member?(attached_ids, &1.id))

    socket
    |> assign(:attached_docs, attached_docs)
    |> assign(:effective_policy_count, length(effective_policies))
    |> assign(:available_documents, available)
  end

  defp find_docs_for_type(all_types, agent_type) do
    case List.keyfind(all_types, agent_type, 0) do
      {^agent_type, docs} -> docs
      nil -> []
    end
  end

  # ── rendering ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-4xl mx-auto space-y-6">
      <.iam_offline_banner hooks_status={@iam_hooks_status} />

      <%!-- Breadcrumb --%>
      <div class="flex items-center gap-2 text-sm text-base-content/60">
        <.link navigate={~p"/iam/agent-types"} class="hover:text-base-content/85 transition-colors">
          Agent Types
        </.link>
        <.icon name="hero-chevron-right" class="size-3.5" />
        <span class="text-base-content/85 font-mono">{@agent_type}</span>
      </div>

      <%!-- Header --%>
      <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-3">
          <.icon name="hero-users" class="size-6 text-primary" />
          <h1 class="text-2xl font-bold font-mono">{@agent_type}</h1>
        </div>

        <.link
          navigate={~p"/iam/simulator?agent_type=#{@agent_type}"}
          class="btn btn-ghost btn-sm"
        >
          <.icon name="hero-beaker" class="size-4" /> Test in simulator
        </.link>
      </div>

      <%!-- Stats row --%>
      <div class="stats shadow bg-base-200">
        <div class="stat">
          <div class="stat-title">Attached documents</div>
          <div class="stat-value text-2xl">{length(@attached_docs)}</div>
        </div>
        <div class="stat">
          <div class="stat-title">Effective policies</div>
          <div class="stat-value text-2xl">{@effective_policy_count}</div>
          <div class="stat-desc">enabled policies across all attached documents</div>
        </div>
      </div>

      <%!-- Attached documents --%>
      <section class="card bg-base-200">
        <div class="card-body p-4 space-y-3">
          <h2 class="card-title text-base">Attached documents</h2>

          <%= if @attached_docs == [] do %>
            <p class="text-sm text-base-content/50 py-2">No documents attached yet.</p>
          <% end %>

          <div class="space-y-2">
            <%= for doc <- @attached_docs do %>
              <div
                id={"attached-doc-#{doc.id}"}
                class="flex items-center justify-between gap-3 p-3 bg-base-100 rounded-lg border border-base-content/10"
              >
                <div class="flex-1 min-w-0">
                  <span class="font-medium">{doc.name}</span>
                  <%= if doc.description do %>
                    <p class="text-xs text-base-content/55 mt-0.5 truncate">{doc.description}</p>
                  <% end %>
                </div>
                <button
                  type="button"
                  class="btn btn-ghost btn-xs text-error"
                  phx-click="detach_document"
                  phx-value-doc_id={doc.id}
                  data-confirm={"Remove \"#{doc.name}\" from #{@agent_type}?"}
                >
                  <.icon name="hero-x-mark" class="size-4" /> Remove
                </button>
              </div>
            <% end %>
          </div>
        </div>
      </section>

      <%!-- Attach document --%>
      <section class="card bg-base-200">
        <div class="card-body p-4 space-y-3">
          <h2 class="card-title text-base">Attach document</h2>

          <%= if @available_documents == [] do %>
            <p class="text-sm text-base-content/50">All documents are already attached.</p>
          <% else %>
            <div class="flex items-end gap-2">
              <label class="form-control flex-1">
                <span class="label-text text-xs">Document</span>
                <select
                  class="select select-bordered select-sm"
                  phx-change="select_attach_doc"
                  name="doc_id"
                >
                  <option value="">— select —</option>
                  <%= for doc <- @available_documents do %>
                    <option value={doc.id} selected={@attach_doc_id == doc.id}>
                      {doc.name}
                    </option>
                  <% end %>
                </select>
              </label>
              <button
                type="button"
                class="btn btn-primary btn-sm"
                phx-click="attach_document"
                disabled={is_nil(@attach_doc_id)}
              >
                Attach
              </button>
            </div>
          <% end %>
        </div>
      </section>
    </div>
    """
  end
end
