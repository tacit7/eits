defmodule EyeInTheSkyWeb.Components.ArchiveConfirmModal do
  @moduledoc false
  use Phoenix.Component

  attr :id, :string, required: true
  attr :show, :boolean, required: true
  attr :count, :integer, required: true
  attr :entity, :string, required: true
  attr :entity_plural, :string, required: true
  attr :cancel_event, :string, required: true
  attr :confirm_event, :string, required: true

  def archive_confirm_modal(assigns) do
    assigns =
      assign(
        assigns,
        :entity_label,
        if(assigns.count == 1, do: assigns.entity, else: assigns.entity_plural)
      )

    ~H"""
    <dialog
      id={@id}
      open={@show}
      aria-labelledby={"#{@id}-title"}
      aria-describedby={"#{@id}-description"}
      class={"eits-modal " <> if(@show, do: "eits-modal-open", else: "")}
    >
      <div class="eits-dialog w-full sm:max-w-sm p-4 pb-[calc(1rem+env(safe-area-inset-bottom))]">
        <h3 id={"#{@id}-title"} class="text-message font-semibold text-base-content">
          Archive {@count} {@entity_label}?
        </h3>
        <p id={"#{@id}-description"} class="mt-2 text-mini leading-relaxed text-base-content/60">
          Archived {@entity_plural} can be restored later.
        </p>

        <div class="eits-panel__actions mt-4">
          <button
            phx-click={@cancel_event}
            class="eits-action eits-action--ghost eits-action--touch"
          >
            Cancel
          </button>
          <button
            phx-click={@confirm_event}
            class="eits-action eits-action--warning-solid eits-action--touch"
          >
            Archive {@count}
          </button>
        </div>
      </div>
      <form method="dialog" class="eits-modal-backdrop">
        <button phx-click={@cancel_event}>close</button>
      </form>
    </dialog>
    """
  end
end
