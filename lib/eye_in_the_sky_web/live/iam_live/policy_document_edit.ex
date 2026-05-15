defmodule EyeInTheSkyWeb.IAMLive.PolicyDocumentEdit do
  @moduledoc """
  Edit form for an existing IAM policy document.

  Only name and description are editable here. Policy membership and agent
  type assignments are managed on the show page.
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
          case IAM.get_policy_document(int_id) do
            {:ok, %PolicyDocument{} = doc} ->
              changeset = PolicyDocument.update_changeset(doc, %{})

              {:ok,
               socket
               |> assign(:page_title, "Edit: #{doc.name}")
               |> assign(:sidebar_tab, :iam)
               |> assign(:sidebar_project, nil)
               |> assign(:document, doc)
               |> assign(:form, to_form(changeset))
               |> assign(:iam_hooks_status, HooksChecker.status())}

            {:error, :not_found} ->
              {:ok,
               socket
               |> put_flash(:error, "Document not found.")
               |> push_navigate(to: ~p"/iam/documents")}
          end
        else
          blank = %PolicyDocument{}
          changeset = PolicyDocument.update_changeset(blank, %{})

          {:ok,
           socket
           |> assign(:page_title, "Edit document")
           |> assign(:sidebar_tab, :iam)
           |> assign(:sidebar_project, nil)
           |> assign(:document, blank)
           |> assign(:form, to_form(changeset))
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
  def handle_event("validate", %{"policy_document" => params}, socket) do
    changeset =
      socket.assigns.document
      |> PolicyDocument.update_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"policy_document" => params}, socket) do
    case IAM.update_policy_document(socket.assigns.document, params) do
      {:ok, doc} ->
        {:noreply,
         socket
         |> put_flash(:info, "Document updated.")
         |> push_navigate(to: ~p"/iam/documents/#{doc.id}")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :form, to_form(Map.put(cs, :action, :update)))}
    end
  end

  # ── rendering ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-4xl mx-auto space-y-6">
      <.iam_offline_banner hooks_status={@iam_hooks_status} />
      <div class="flex items-center gap-3">
        <.link navigate={~p"/iam/documents/#{@document.id}"} class="btn btn-ghost btn-sm">
          <.icon name="hero-arrow-left" class="size-4" />
        </.link>
        <.icon name="hero-pencil-square" class="size-6 text-primary" />
        <h1 class="text-2xl font-bold">Edit document</h1>
      </div>

      <.form
        for={@form}
        id="policy-document-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <section class="card bg-base-200">
          <div class="card-body p-4 space-y-4">
            <.input
              field={@form[:name]}
              type="text"
              label="Name"
              required
            />

            <.input
              field={@form[:description]}
              type="textarea"
              label="Description (optional)"
              rows="3"
            />
          </div>
        </section>

        <div class="flex justify-end gap-2">
          <.link navigate={~p"/iam/documents/#{@document.id}"} class="btn btn-ghost">
            Cancel
          </.link>
          <button type="submit" class="btn btn-primary">
            Save changes
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
