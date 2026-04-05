defmodule EyeInTheSky.Claude.SessionFileLocator do
  @moduledoc """
  Owns JSONL session file path construction for ~/.claude/projects/.

  Two callers previously diverged:
  - SessionReader: escapes the project path (/ and . → -)
  - JsonlStorage: uses raw project_id as the directory name

  Both strategies are preserved here under a single roof.
  """

  @doc """
  Constructs and checks the path for a session JSONL file given a raw project path.
  Applies escape_project_path/1 to derive the directory name.

  Returns {:ok, path} if the file exists, {:error, :not_found} otherwise.
  """
  def locate(session_id, project_path) do
    file_path = build_path(escape_project_path(project_path), session_id)

    if File.exists?(file_path) do
      {:ok, file_path}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Returns the JSONL file path for a session identified by a raw project_id directory name.
  This is the convention used by JsonlStorage, where project_id is already the
  escaped directory name on disk.

  Does not check existence — callers own that responsibility.
  """
  def locate_by_id(project_id, session_id) do
    build_path(project_id, session_id)
  end

  @doc """
  Returns true if the JSONL file for (session_id, project_path) exists on disk.
  Uses the same escape logic as locate/2.
  """
  def exists?(session_id, project_path) do
    file_path = build_path(escape_project_path(project_path), session_id)
    File.exists?(file_path)
  end

  @doc """
  Escapes a project path for Claude's directory naming convention.
  Example: "/Users/user/projects/myapp" -> "-Users-user-projects-myapp"
  """
  def escape_project_path(path) do
    path
    |> String.replace("/", "-")
    |> String.replace(".", "-")
  end

  defp build_path(dir, session_id) do
    home = System.get_env("HOME")
    Path.join([home, ".claude", "projects", dir, "#{session_id}.jsonl"])
  end
end
