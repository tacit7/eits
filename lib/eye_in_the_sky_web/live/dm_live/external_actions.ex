defmodule EyeInTheSkyWeb.DmLive.ExternalActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias EyeInTheSkyWeb.Live.Shared.SessionHelpers

  @uuid_pattern ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @thread_id_pattern ~r/\A[^\s]+\z/

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
    session_id = socket.assigns.session_uuid
    provider = socket.assigns.session.provider || "claude"

    with :ok <- validate_resume_id(provider, session_id),
         {:ok, resume_cmd} <- build_resume_command(provider, session_id) do
      dir =
        case SessionHelpers.resolve_project_path(socket.assigns.session, socket.assigns.agent) do
          {:ok, path} -> path
          {:error, _} -> "~"
        end

      command = "cd #{shell_escape(dir)} && #{resume_cmd}"
      safe_command = applescript_escape(command)

      script = """
      tell application "iTerm"
        activate
        set newWindow to (create window with default profile)
        tell current session of newWindow
          write text "#{safe_command}"
        end tell
      end tell
      """

      System.cmd("osascript", ["-e", script], stderr_to_stdout: true)
      {:noreply, socket}
    else
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp validate_resume_id("codex", session_id) when is_binary(session_id) do
    if Regex.match?(@thread_id_pattern, session_id) do
      :ok
    else
      {:error, "Invalid Codex thread ID"}
    end
  end

  defp validate_resume_id(_provider, session_id) when is_binary(session_id) do
    if Regex.match?(@uuid_pattern, session_id) do
      :ok
    else
      {:error, "Invalid session UUID"}
    end
  end

  defp build_resume_command("codex", session_id) do
    {:ok, "codex resume #{shell_escape(session_id)}"}
  end

  defp build_resume_command("claude", session_id) do
    {:ok, "claude --dangerously-skip-permissions -r #{shell_escape(session_id)}"}
  end

  defp build_resume_command("gemini", session_id) do
    {:ok, "gemini --resume #{shell_escape(session_id)}"}
  end

  defp build_resume_command(provider, _session_id) do
    {:error, "Unsupported provider: #{provider}"}
  end

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end

  defp applescript_escape(value) when is_binary(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end
end
