defmodule EyeInTheSkyWeb.IAMLive.PolicyDocumentNew do
  @moduledoc """
  Create form for a new IAM policy document.

  Only collects name and description. Policy membership and agent type
  assignments are managed on the show page after creation.
  """
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.IAMLive.IAMComponents

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.HooksChecker
  alias EyeInTheSky.IAM.PolicyDocument
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers

  @impl true
  def mount(_params, _session, socket) do
    changeset = PolicyDocument.create_changeset(%PolicyDocument{}, %{})

    {:ok,
     socket
     |> assign(:page_title, "New Policy Document")
     |> assign(:sidebar_tab, :iam)
     |> assign(:sidebar_project, nil)
     |> assign(:form, to_form(changeset))
     |> assign(:iam_hooks_status, HooksChecker.status())}
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  @impl true
  def handle_event("validate", %{"policy_document" => params}, socket) do
    changeset =
      %PolicyDocument{}
      |> PolicyDocument.create_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"policy_document" => params}, socket) do
    case IAM.create_policy_document(params) do
      {:ok, doc} ->
        {:noreply,
         socket
         |> put_flash(:info, "Document \"#{doc.name}\" created.")
         |> push_navigate(to: ~p"/iam/documents/#{doc.id}")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :form, to_form(Map.put(cs, :action, :insert)))}
    end
  end

  # ── rendering ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-4xl mx-auto space-y-6">
      <.iam_offline_banner hooks_status={@iam_hooks_status} />
      <div class="flex items-center gap-3">
        <.link navigate={~p"/iam/documents"} class="btn btn-ghost btn-sm">
          <.icon name="hero-arrow-left" class="size-4" />
        </.link>
        <.icon name="hero-document-plus" class="size-6 text-primary" />
        <h1 class="text-2xl font-bold">New Policy Document</h1>
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
              placeholder="e.g. ReadOnly, NoDeployments"
              required
            />

            <.input
              field={@form[:description]}
              type="textarea"
              label="Description (optional)"
              placeholder="What policies this document contains and which agent types it targets"
              rows="3"
            />
          </div>
        </section>

        <div class="flex justify-end gap-2">
          <.link navigate={~p"/iam/documents"} class="btn btn-ghost">
            Cancel
          </.link>
          <button type="submit" class="btn btn-primary">
            Create document
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
