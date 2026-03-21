defmodule EyeInTheSkyWeb.Live.Shared.DmModelHelpers do
  require Logger

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias EyeInTheSky.Sessions

  def handle_toggle_model_menu(socket) do
    overlay = if socket.assigns.active_overlay == :model_menu, do: nil, else: :model_menu
    {:noreply, assign(socket, :active_overlay, overlay)}
  end

  def handle_toggle_effort_menu(socket) do
    overlay = if socket.assigns.active_overlay == :effort_menu, do: nil, else: :effort_menu
    {:noreply, assign(socket, :active_overlay, overlay)}
  end

  def handle_toggle_thinking(socket) do
    {:noreply, assign(socket, :thinking_enabled, !socket.assigns.thinking_enabled)}
  end

  def handle_toggle_live_stream(params, socket) do
    enabled =
      case params do
        %{"enabled" => true} -> true
        %{"enabled" => "true"} -> true
        _ -> !socket.assigns.show_live_stream
      end

    {:noreply, assign(socket, :show_live_stream, enabled)}
  end

  def handle_select_model(%{"model" => model, "effort" => effort}, socket) do
    session = socket.assigns.session

    socket =
      case Sessions.update_session(session, %{model: model}) do
        {:ok, _updated} ->
          socket

        {:error, changeset} ->
          Logger.error("Failed to persist model selection: #{inspect(changeset.errors)}")
          put_flash(socket, :error, "Failed to save model selection")
      end

    effort = if effort == "" and model == "opus", do: "medium", else: effort

    socket =
      socket
      |> assign(:selected_model, model)
      |> assign(:selected_effort, effort)
      |> assign(:active_overlay, nil)

    {:noreply, socket}
  end

  def handle_select_effort(%{"effort" => effort}, socket) do
    {:noreply, socket |> assign(:selected_effort, effort) |> assign(:active_overlay, nil)}
  end

  def handle_set_max_budget(%{"value" => value}, socket) do
    budget =
      case Float.parse(value) do
        {f, _} when f > 0 -> f
        _ -> nil
      end

    {:noreply, assign(socket, :max_budget_usd, budget)}
  end
end
