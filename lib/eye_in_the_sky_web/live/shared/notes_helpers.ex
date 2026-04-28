defmodule EyeInTheSkyWeb.Live.Shared.NotesHelpers do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias EyeInTheSky.Notes

  # ---------------------------------------------------------------------------
  # Event handlers with reload_fn callback
  # Each LiveView passes its own load_notes/1 since scoping differs.
  # ---------------------------------------------------------------------------

  def handle_search(%{"query" => query}, socket, reload_fn) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> reload_fn.()}
  end

  def handle_sort_notes(%{"by" => sort_by}, socket, reload_fn) do
    {:noreply, socket |> assign(:sort_by, sort_by) |> reload_fn.()}
  end

  def handle_filter_type(%{"type" => type}, socket, reload_fn) do
    {:noreply, socket |> assign(:type_filter, type) |> reload_fn.()}
  end

  def handle_toggle_starred_filter(_params, socket, reload_fn) do
    {:noreply,
     socket
     |> assign(:starred_filter, !socket.assigns.starred_filter)
     |> reload_fn.()}
  end

  def handle_toggle_star(params, socket, reload_fn) do
    note_id = params["note_id"] || params["note-id"] || params["value"]

    case Notes.toggle_starred(note_id) do
      {:ok, _note} ->
        {:noreply, reload_fn.(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to toggle star")}
    end
  end

  def handle_delete_note(params, socket, reload_fn) do
    note_id = params["note_id"] || params["note-id"] || params["value"]

    case Notes.get_note(note_id) do
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Note not found")}

      {:ok, note} ->
        case Notes.delete_note(note) do
          {:ok, _} ->
            {:noreply, reload_fn.(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete note")}
        end
    end
  end
end
