defmodule EyeInTheSkyWebWeb.Live.Shared.NotesHelpers do
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias EyeInTheSkyWeb.Notes

  # ---------------------------------------------------------------------------
  # Event handlers with reload_fn callback
  # Each LiveView passes its own load_notes/1 since scoping differs.
  # ---------------------------------------------------------------------------

  def handle_search(%{"query" => query}, socket, reload_fn) do
    effective_query = if String.length(String.trim(query)) >= 4, do: query, else: ""

    {:noreply,
     socket
     |> assign(:search_query, effective_query)
     |> reload_fn.()}
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

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to toggle star")}
    end
  end
end
