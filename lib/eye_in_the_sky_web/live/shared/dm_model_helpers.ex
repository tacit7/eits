defmodule EyeInTheSkyWeb.Live.Shared.DmModelHelpers do
  @moduledoc false
  require Logger

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  import EyeInTheSkyWeb.Live.Shared.OverlayHelpers

  alias EyeInTheSky.Agents.ModelConfig
  alias EyeInTheSky.Sessions

  def handle_toggle_effort_menu(socket) do
    overlay = toggle_overlay(socket.assigns.active_overlay, :effort_menu)
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

  def handle_select_model(%{"provider" => provider, "model" => model} = params, socket) do
    session = socket.assigns.session
    effort = params["effort"] || ""

    cond do
      # allow_provider_switch?: false — the composer never lets a selection
      # change the session's own provider (spec §5.2). A payload claiming
      # otherwise is rejected outright; this is the untrusted-client-input
      # revalidation the spec requires (§5.4).
      provider != session.provider ->
        {:noreply, put_flash(socket, :error, "Cannot switch provider mid-conversation")}

      not ModelConfig.valid_model?(provider, model) ->
        {:noreply, put_flash(socket, :error, "Invalid model selection")}

      true ->
        {:noreply, persist_model_selection(socket, session, model, effort)}
    end
  end

  # Back-compat clause: the pre-Task-7 dropdown only ever sent
  # %{"model", "effort"} with no "provider" key. Kept so any stale client
  # bundle (mid-deploy) doesn't crash; treats the session's own provider as
  # implicit, same as before this change.
  def handle_select_model(%{"model" => model, "effort" => effort}, socket) do
    session = socket.assigns.session
    {:noreply, persist_model_selection(socket, session, model, effort)}
  end

  defp persist_model_selection(socket, session, model, effort) do
    socket =
      case Sessions.update_session(session, %{model: model}) do
        {:ok, _updated} ->
          socket

        {:error, changeset} ->
          Logger.error("Failed to persist model selection: #{inspect(changeset.errors)}")
          put_flash(socket, :error, "Failed to save model selection")
      end

    is_opus = String.starts_with?(model, "claude-opus") or model in ["opus", "opus[1m]"]
    effort = if effort == "" and is_opus, do: "medium", else: effort

    socket
    |> assign(:selected_model, model)
    |> assign(:selected_effort, effort)
    |> assign(:active_overlay, nil)
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
