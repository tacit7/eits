defmodule EyeInTheSkyWeb.Components.ArchiveConfirmModalTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.ArchiveConfirmModal

  test "renders count-first archive copy and accessible dialog labels" do
    html =
      render_component(&ArchiveConfirmModal.archive_confirm_modal/1,
        id: "test-archive-confirm-modal",
        show: true,
        count: 3,
        entity: "session",
        entity_plural: "sessions",
        cancel_event: "cancel_archive_selected",
        confirm_event: "archive_selected"
      )

    assert html =~ ~s(id="test-archive-confirm-modal")
    assert html =~ ~s(open)
    assert html =~ ~s(aria-labelledby="test-archive-confirm-modal-title")
    assert html =~ ~s(aria-describedby="test-archive-confirm-modal-description")
    assert html =~ "Archive 3 sessions?"
    assert html =~ "Archived sessions can be restored later."
    assert html =~ "Archive 3"
    assert html =~ ~s(phx-click="cancel_archive_selected")
    assert html =~ ~s(phx-click="archive_selected")
  end

  test "singularizes the archive title for one selected item" do
    html =
      render_component(&ArchiveConfirmModal.archive_confirm_modal/1,
        id: "test-archive-confirm-modal",
        show: true,
        count: 1,
        entity: "team",
        entity_plural: "teams",
        cancel_event: "cancel_archive_selected",
        confirm_event: "archive_selected"
      )

    assert html =~ "Archive 1 team?"
    refute html =~ "Archive 1 teams?"
  end
end
