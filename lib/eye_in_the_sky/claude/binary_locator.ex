defmodule EyeInTheSky.Claude.BinaryLocator do
  @moduledoc """
  Locates the `claude` binary by searching PATH, standard install paths,
  and NVM-managed Node.js version directories.

  Results are cached via `:persistent_term` by `EyeInTheSky.CLI.Port.find_binary/2`.
  """

  # NOTE: must be a function, not a module attribute — Path.expand("~") in a
  # module attribute runs at COMPILE time on the build machine, baking the
  # builder's home directory into the release. On any machine with a different
  # username (e.g. the packaged desktop app), ~/.local/bin/claude was never
  # actually checked.
  defp standard_paths do
    [
      "/usr/local/bin/claude",
      "/opt/homebrew/bin/claude",
      Path.expand("~/.local/bin/claude")
    ]
  end

  @doc """
  Locates the `claude` binary. Checks in order:
  1. PATH (`System.find_executable/1`)
  2. Standard install paths (`standard_paths/0`)
  3. NVM-managed Node.js versions

  Returns `{:ok, path}` or `{:error, {:binary_not_found, ...}}`.
  """
  @spec find() :: {:ok, String.t()} | {:error, term()}
  def find do
    nvm_dir = System.get_env("NVM_DIR") || Path.expand("~/.nvm")

    cond do
      path = System.find_executable("claude") ->
        {:ok, path}

      path = EyeInTheSky.CLI.Port.find_in_standard_paths(standard_paths()) ->
        {:ok, path}

      path = find_in_nvm() ->
        {:ok, path}

      true ->
        {:error, {:binary_not_found, checked_paths: standard_paths(), nvm_dir: nvm_dir}}
    end
  end

  # ---------------------------------------------------------------------------
  # NVM scanning
  # ---------------------------------------------------------------------------

  defp find_in_nvm do
    nvm_dir = System.get_env("NVM_DIR") || Path.expand("~/.nvm")
    versions_dir = Path.join(nvm_dir, "versions/node")

    if File.dir?(versions_dir) do
      versions_dir
      |> File.ls!()
      |> Enum.filter(&semver_dir?/1)
      |> Enum.sort_by(&parse_version/1, {:desc, Version})
      |> Enum.find_value(&find_claude_in_nvm_dir(versions_dir, &1))
    else
      nil
    end
  end

  defp find_claude_in_nvm_dir(versions_dir, dir) do
    path = Path.join([versions_dir, dir, "bin", "claude"])
    if File.exists?(path), do: path
  end

  @doc false
  def semver_dir?("v" <> rest), do: match?({:ok, _}, Version.parse(rest))
  def semver_dir?(_), do: false

  @doc false
  def parse_version("v" <> rest) do
    case Version.parse(rest) do
      {:ok, v} -> v
      :error -> Version.parse!("0.0.0")
    end
  end
end
