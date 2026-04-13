defmodule EyeInTheSkyWeb.NoteLive.Helpers do
  @moduledoc "Shared helpers for NoteLive.Edit and NoteLive.New."

  @valid_return_paths ["/notes", ~r|^/projects/\d+/notes$|]

  @doc """
  Returns `path` if it is a safe whitelisted return path, else "/notes".
  """
  def safe_return_to(path) when is_binary(path) do
    if String.starts_with?(path, "/") and
         Enum.any?(@valid_return_paths, fn
           p when is_binary(p) -> p == path
           r -> Regex.match?(r, path)
         end),
       do: path,
       else: "/notes"
  end

  def safe_return_to(_), do: "/notes"
end
