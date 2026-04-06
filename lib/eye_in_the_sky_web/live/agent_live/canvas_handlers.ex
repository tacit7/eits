defmodule EyeInTheSkyWeb.AgentLive.CanvasHandlers do
  @moduledoc """
  Handles canvas-related events for AgentLive.Index:
  show_new_canvas_form, add_to_canvas, add_to_new_canvas.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias EyeInTheSkyWeb.Canvases
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  def handle_event("show_new_canvas_form", %{"agent-id" => id}, socket) do
    {:noreply, assign(socket, :show_new_canvas_for, id)}
  end

  def handle_event("add_to_canvas", %{"canvas-id" => cid, "session-id" => sid}, socket) do
    with canvas_id when not is_nil(canvas_id) <- parse_int(cid),
         session_id when not is_nil(session_id) <- parse_int(sid),
         %{} = canvas <- Canvases.get_canvas(canvas_id) do
      Canvases.add_session(canvas_id, session_id)

      Phoenix.LiveView.send_update(EyeInTheSkyWeb.Components.CanvasOverlayComponent,
        id: "canvas-overlay",
        action: :open_canvas,
        canvas_id: canvas_id
      )

      {:noreply, put_flash(socket, :info, "Added to #{canvas.name}")}
    else
      nil -> {:noreply, put_flash(socket, :error, "Invalid canvas or session ID")}
      _ -> {:noreply, put_flash(socket, :error, "Canvas not found")}
    end
  end

  def handle_event("add_to_new_canvas", %{"session_id" => sid, "canvas_name" => name}, socket) do
    case parse_int(sid) do
      nil ->
        {:noreply, socket}

      session_id ->
        canvas_name =
          if name && String.trim(name) != "",
            do: String.trim(name),
            else: "Canvas #{:os.system_time(:second)}"

        case Canvases.create_canvas(%{name: canvas_name}) do
          {:ok, canvas} ->
            Canvases.add_session(canvas.id, session_id)

            Phoenix.LiveView.send_update(EyeInTheSkyWeb.Components.CanvasOverlayComponent,
              id: "canvas-overlay",
              action: :open_canvas,
              canvas_id: canvas.id
            )

            {:noreply, put_flash(socket, :info, "Added to #{canvas.name}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to create canvas")}
        end
    end
  end
end
