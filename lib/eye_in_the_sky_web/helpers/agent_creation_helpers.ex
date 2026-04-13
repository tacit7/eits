defmodule EyeInTheSkyWeb.Helpers.AgentCreationHelpers do
  @moduledoc """
  Shared opts builder for AgentManager.create_agent/1 calls.

  Both ChatLive and AgentLive.Index were independently constructing the same
  keyword list. This module centralises that logic so they stay in sync.
  """

  import EyeInTheSkyWeb.ControllerHelpers, only: [maybe_opt: 3, parse_int: 1]
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [parse_budget: 1]

  @doc """
  Build the opts keyword list for AgentManager.create_agent/1.

  `params` is the raw LiveView event params map.
  `overrides` is a keyword list of caller-resolved values:
    - `project_path:` — callers resolve this from their local project struct/list
    - `description:` — human-readable agent name
    - `instructions:` — initial prompt / instructions text
  """
  @spec build_opts(map(), keyword()) :: keyword()
  def build_opts(params, overrides \\ []) do
    max_turns = parse_int(params["max_turns"])

    worktree =
      case params["worktree"] do
        nil -> nil
        "" -> nil
        v -> String.trim(v)
      end

    advanced_opts =
      []
      |> maybe_opt(:permission_mode, params["permission_mode"])
      |> maybe_opt(:max_turns, if(is_integer(max_turns) and max_turns > 0, do: max_turns))
      |> maybe_opt(:add_dir, params["add_dir"])
      |> maybe_opt(:mcp_config, params["mcp_config"])
      |> maybe_opt(:plugin_dir, params["plugin_dir"])
      |> maybe_opt(:settings_file, params["settings_file"])
      |> maybe_opt(:chrome, if(params["chrome"] == "true", do: true))
      |> maybe_opt(:sandbox, if(params["sandbox"] == "true", do: true))

    base = [
      agent_type: params["agent_type"] || "claude",
      model: params["model"] || "sonnet",
      effort_level: params["effort_level"],
      max_budget_usd: parse_budget(params["max_budget_usd"]),
      project_id: params["project_id"],
      project_path: Keyword.get(overrides, :project_path),
      description: Keyword.get(overrides, :description),
      instructions: Keyword.get(overrides, :instructions),
      agent: params["agent"],
      worktree: worktree,
      eits_workflow: params["eits_workflow"] || "1"
    ]

    base ++ advanced_opts
  end
end
