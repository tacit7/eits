defmodule EyeInTheSkyWebWeb.DmLive.Checkpoints do
  @moduledoc """
  Checkpoint-related event handlers extracted from DmLive.

  All public functions return {:noreply, socket} and can be called directly
  from handle_event/3 clauses in DmLive.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]
  use EyeInTheSkyWebWeb, :verified_routes

  alias EyeInTheSkyWeb.Checkpoints

  def handle_toggle_create(socket) do
    overlay = if socket.assigns.active_overlay == :checkpoint, do: nil, else: :checkpoint
    {:noreply, assign(socket, :active_overlay, overlay)}
  end

  def handle_create(params, socket) do
    session_id = socket.assigns.session_id
    name = String.trim(params["name"] || "")
    description = String.trim(params["description"] || "")
    project_path = resolve_project_path(socket)

    attrs = %{
      name: if(name == "", do: nil, else: name),
      description: if(description == "", do: nil, else: description),
      project_path: project_path
    }

    case Checkpoints.create_checkpoint(session_id, attrs) do
      {:ok, _checkpoint} ->
        socket =
          socket
          |> assign(:active_overlay, nil)
          |> assign(:checkpoints, Checkpoints.list_checkpoints_for_session(session_id))

        {:noreply, put_flash(socket, :info, "Checkpoint saved")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create checkpoint: #{inspect(reason)}")}
    end
  end

  def handle_restore(%{"id" => id_str}, socket) do
    session_id = socket.assigns.session_id

    with {id, ""} <- Integer.parse(id_str),
         {:ok, checkpoint} <- Checkpoints.get_checkpoint(id),
         true <- checkpoint.session_id == session_id,
         {:ok, _deleted} <- Checkpoints.restore_checkpoint(checkpoint) do
      socket =
        socket
        |> assign(:checkpoints, Checkpoints.list_checkpoints_for_session(session_id))

      {:noreply, put_flash(socket, :info, "Restored to checkpoint")}
    else
      false ->
        {:noreply, put_flash(socket, :error, "Checkpoint does not belong to this session")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Checkpoint not found")}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to restore checkpoint")}
    end
  end

  def handle_fork(%{"id" => id_str}, socket) do
    session_id = socket.assigns.session_id

    with {id, ""} <- Integer.parse(id_str),
         {:ok, checkpoint} <- Checkpoints.get_checkpoint(id),
         true <- checkpoint.session_id == session_id,
         {:ok, new_session} <- Checkpoints.fork_checkpoint(checkpoint) do
      {:noreply,
       socket
       |> put_flash(:info, "Forked to new session ##{new_session.id}")
       |> push_navigate(to: ~p"/dm/#{new_session.id}")}
    else
      false ->
        {:noreply, put_flash(socket, :error, "Checkpoint does not belong to this session")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Checkpoint not found")}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to fork checkpoint")}
    end
  end

  def handle_delete(%{"id" => id_str}, socket) do
    session_id = socket.assigns.session_id

    with {id, ""} <- Integer.parse(id_str),
         {:ok, checkpoint} <- Checkpoints.get_checkpoint(id),
         true <- checkpoint.session_id == session_id,
         {:ok, _} <- Checkpoints.delete_checkpoint(checkpoint) do
      {:noreply,
       assign(socket, :checkpoints, Checkpoints.list_checkpoints_for_session(session_id))}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Failed to delete checkpoint")}
    end
  end

  # Resolves the project path from session/agent assigns.
  # Mirrors DmLive.resolve_project_path/2 but reads from socket directly.
  defp resolve_project_path(socket) do
    session = socket.assigns.session
    agent = socket.assigns.agent

    cond do
      session.git_worktree_path -> session.git_worktree_path
      agent.git_worktree_path -> agent.git_worktree_path
      agent.project && agent.project.path -> agent.project.path
      true -> nil
    end
  end
end
