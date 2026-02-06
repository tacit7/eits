defmodule EyeInTheSkyWeb.Claude.BinaryLocator do
  @moduledoc """
  Finds the Claude CLI binary using multiple strategies.
  """

  @spec find_claude_binary() :: {:ok, String.t()} | {:error, String.t()}
  def find_claude_binary do
    cond do
      path = System.find_executable("claude") ->
        {:ok, path}

      path = find_in_standard_paths() ->
        {:ok, path}

      path = find_in_nvm() ->
        {:ok, path}

      true ->
        {:error, "Claude binary not found in PATH, standard locations, or NVM"}
    end
  end

  defp find_in_standard_paths do
    [
      "/usr/local/bin/claude",
      "/opt/homebrew/bin/claude",
      Path.expand("~/.local/bin/claude")
    ]
    |> Enum.find(&File.exists?/1)
  end

  defp find_in_nvm do
    nvm_dir = System.get_env("NVM_DIR") || Path.expand("~/.nvm")
    versions_dir = Path.join(nvm_dir, "versions/node")

    if File.dir?(versions_dir) do
      versions_dir
      |> File.ls!()
      |> Enum.map(&Path.join([versions_dir, &1, "bin", "claude"]))
      |> Enum.filter(&File.exists?/1)
      |> List.first()
    else
      nil
    end
  end
end
