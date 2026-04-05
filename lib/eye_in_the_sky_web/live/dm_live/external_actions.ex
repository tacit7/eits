defmodule EyeInTheSkyWeb.DmLive.ExternalActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias EyeInTheSkyWeb.Live.Shared.SessionHelpers

  @uuid_pattern ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  def handle_load_diff(hash, socket) do
    if Map.has_key?(socket.assigns.diff_cache, hash) do
      {:noreply, socket}
    else
      diff = fetch_git_diff(hash, socket)
      cache = Map.put(socket.assigns.diff_cache, hash, diff)
      {:noreply, assign(socket, :diff_cache, cache)}
    end
  end

  defp fetch_git_diff(hash, socket) do
    case SessionHelpers.resolve_project_path(socket.assigns.session, socket.assigns.agent) do
      {:ok, project_path} ->
        case System.cmd("git", ["-C", project_path, "show", hash, "--unified=5"],
               stderr_to_stdout: false
             ) do
          {output, 0} -> output
          _ -> :error
        end

      _ ->
        :error
    end
  end

  def handle_open_iterm(socket) do
    session_uuid = socket.assigns.session_uuid

    unless Regex.match?(@uuid_pattern, session_uuid) do
      {:noreply, put_flash(socket, :error, "Invalid session UUID")}
    else
      dir =
        case SessionHelpers.resolve_project_path(socket.assigns.session, socket.assigns.agent) do
          {:ok, path} -> path
          {:error, _} -> "~"
        end

      safe_dir = String.replace(dir, "\"", "\\\"")

      script = """
      tell application "iTerm"
        activate
        set newWindow to (create window with default profile)
        tell current session of newWindow
          write text "cd #{safe_dir} && claude --dangerously-skip-permissions -r #{session_uuid}"
        end tell
      end tell
      """

      System.cmd("osascript", ["-e", script], stderr_to_stdout: true)
      {:noreply, socket}
    end
  end
end
