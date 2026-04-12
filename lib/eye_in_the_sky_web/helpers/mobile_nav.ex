defmodule EyeInTheSkyWeb.Helpers.MobileNav do
  @moduledoc """
  Deterministic mapping from request path to mobile bottom-nav active tab.

  Centralizes nav active-state logic so individual LiveViews don't need to
  set the correct assigns for the mobile nav to highlight correctly.
  """

  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  @type nav_tab :: :sessions | :tasks | :notes | :project | :none

  @doc """
  Returns the active mobile nav tab for the given request path.

  ## Mapping

  - `/projects/:id` and all `/projects/:id/*` sub-routes → `:project`
  - `/dm/:session_id` with no project context → `:none`
  - `/tasks` → `:tasks`
  - `/notes` → `:notes`
  - `/`, `/sessions` → `:sessions`
  - Everything else (settings, usage, prompts, etc.) → `:none`
  """
  @spec active_tab_for_path(String.t() | nil) :: nav_tab()
  def active_tab_for_path(nil), do: :sessions

  def active_tab_for_path(path) when is_binary(path) do
    cond do
      project_route?(path) -> :project
      path == "/tasks" -> :tasks
      path == "/notes" -> :notes
      path in ["/", "/sessions"] -> :sessions
      String.starts_with?(path, "/dm/") -> :sessions
      true -> :none
    end
  end

  @doc """
  Returns true if the path is a project sub-route (any /projects/:id/* route).
  """
  @spec project_route?(String.t()) :: boolean()
  def project_route?(path) when is_binary(path) do
    String.match?(path, ~r{^/projects/\d+(/.*)?$})
  end

  def project_route?(_), do: false

  @doc """
  Extracts the integer project ID from a project route path.
  Returns nil for non-project paths.
  """
  @spec project_id_from_path(String.t() | nil) :: integer() | nil
  def project_id_from_path(nil), do: nil

  def project_id_from_path(path) when is_binary(path) do
    case Regex.run(~r{^/projects/(\d+)(/.*)?$}, path) do
      [_, id_str | _] -> parse_int(id_str)
      _ -> nil
    end
  end
end
