defmodule EyeInTheSkyWeb.Helpers.AgentCreationHelpers do
  @moduledoc """
  Shared opts builder for AgentManager.create_agent/1 calls.

  Both ChatLive and AgentLive.Index were independently constructing the same
  keyword list. This module centralises that logic so they stay in sync.
  """

  import EyeInTheSkyWeb.ControllerHelpers, only: [maybe_opt: 3, parse_int: 1]
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [parse_budget: 1]

  alias EyeInTheSky.Claude.AgentFileScanner

  @doc """
  Build the opts keyword list for AgentManager.create_agent/1.

  `params` is the raw LiveView event params map.
  `overrides` is a keyword list of caller-resolved values:
    - `project_path:` — callers resolve this from their local project struct/list
    - `description:` — human-readable agent name
    - `instructions:` — initial prompt / instructions text

  The `agent` param is validated against known slugs for the resolved project_path.
  An unrecognised slug is silently dropped (treated as no agent selected).
  """
  @spec build_opts(map(), keyword()) :: keyword()
  def build_opts(params, overrides \\ []) do
    max_turns = parse_int(params["max_turns"])
    project_path = Keyword.get(overrides, :project_path)

    worktree =
      case params["worktree"] do
        nil -> nil
        "" -> nil
        v -> String.trim(v)
      end

    from_pr = parse_int(params["from_pr"])

    advanced_opts =
      []
      |> maybe_opt(:permission_mode, params["permission_mode"])
      |> maybe_opt(:max_turns, if(is_integer(max_turns) and max_turns > 0, do: max_turns))
      |> maybe_opt(:fallback_model, params["fallback_model"])
      |> maybe_opt(:from_pr, if(is_integer(from_pr) and from_pr > 0, do: from_pr))
      |> maybe_opt(:output_format, params["output_format"])
      |> maybe_opt(:input_format, params["input_format"])
      |> maybe_opt(:json_schema, params["json_schema"])
      |> maybe_opt(:allowed_tools, params["allowed_tools"])
      |> maybe_opt(:permission_prompt_tool, params["permission_prompt_tool"])
      |> maybe_opt(:add_dir, params["add_dir"])
      |> maybe_opt(:mcp_config, params["mcp_config"])
      |> maybe_opt(:plugin_dir, params["plugin_dir"])
      |> maybe_opt(:settings_file, params["settings_file"])
      |> maybe_opt(:agents_json, params["agents_json"])
      |> maybe_opt(:agent_flag, params["agent_flag"])
      |> maybe_opt(:system_prompt, params["system_prompt"])
      |> maybe_opt(:system_prompt_file, params["system_prompt_file"])
      |> maybe_opt(:append_system_prompt, params["append_system_prompt"])
      |> maybe_opt(:append_system_prompt_file, params["append_system_prompt_file"])
      |> maybe_opt(:debug, params["debug"])
      |> maybe_opt(:bare, if(params["bare"] == "true", do: true))
      |> maybe_opt(:verbose, if(params["verbose"] == "true", do: true))
      |> maybe_opt(:include_partial_messages, if(params["include_partial_messages"] == "true", do: true))
      |> maybe_opt(:no_session_persistence, if(params["no_session_persistence"] == "true", do: true))
      |> maybe_opt(:chrome, if(params["chrome"] == "true", do: true))
      |> maybe_opt(:sandbox, if(params["sandbox"] == "true", do: true))
      |> maybe_opt(:dangerously_skip_permissions, if(params["dangerously_skip_permissions"] == "true", do: true))

    base = [
      agent_type: params["agent_type"] || "claude",
      model: params["model"] || "sonnet",
      effort_level: params["effort_level"],
      max_budget_usd: parse_budget(params["max_budget_usd"]),
      project_id: params["project_id"],
      project_path: project_path,
      description: Keyword.get(overrides, :description),
      instructions: Keyword.get(overrides, :instructions),
      agent: validate_agent_slug(params["agent"], project_path),
      worktree: worktree,
      eits_workflow: params["eits_workflow"] || "1"
    ]

    base ++ advanced_opts
  end

  # Accepts the submitted agent slug only if it matches a known agent definition
  # for the given project_path. Returns nil for blank, unknown, or when project_path
  # is nil (no project context, so no agents to validate against).
  defp validate_agent_slug(nil, _), do: nil
  defp validate_agent_slug("", _), do: nil
  defp validate_agent_slug(_, nil), do: nil

  defp validate_agent_slug(slug, project_path) do
    slug = String.trim(slug)
    valid_slugs = project_path |> AgentFileScanner.scan() |> Enum.map(& &1.slug)
    if slug in valid_slugs, do: slug, else: nil
  end
end
