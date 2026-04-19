defmodule EyeInTheSky.IAM.Normalizer do
  @moduledoc """
  Converts raw Claude Code hook payloads into `EyeInTheSky.IAM.Context` structs.

  Per-tool extractors know which field in `tool_input` carries the primary
  resource (`command` for Bash, `file_path` for Edit/Write, etc.). Unknown
  tools fall through to `:unknown` resource_type without failing.

  Hook payloads are expected to carry at least one of the documented Claude
  hook fields (`tool_name`, `tool_input`, `session_id`, `cwd`,
  `hook_event_name`, optionally `agent_type`/`agent_name`/`subagent_type`).
  Missing fields produce a best-effort context with sensible defaults; the
  controller that calls this is responsible for deciding the fail-safe
  behavior when the context is unusable.
  """

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.ProjectIdentity

  @type raw_payload :: map()

  @doc "Build an `IAM.Context` from a raw Claude hook payload."
  @spec from_hook_payload(raw_payload()) :: Context.t()
  def from_hook_payload(payload) when is_map(payload) do
    identity = ProjectIdentity.resolve(payload)
    tool_input = Map.get(payload, "tool_input") || Map.get(payload, :tool_input) || %{}
    tool = Map.get(payload, "tool_name") || Map.get(payload, :tool_name)

    {resource_type, resource_path, resource_content} = extract_resource(tool, tool_input)

    Context.new(%{
      event: normalize_event(payload),
      agent_type: extract_agent_type(payload),
      project_id: identity.project_id,
      project_path: identity.project_path,
      tool: tool,
      resource_type: resource_type,
      resource_path: resource_path,
      resource_content: resource_content,
      raw_tool_input: tool_input,
      tool_response: Map.get(payload, "tool_response") || Map.get(payload, :tool_response),
      prompt: Map.get(payload, "prompt") || Map.get(payload, :prompt),
      session_uuid: Map.get(payload, "session_id") || Map.get(payload, :session_uuid),
      metadata: Map.get(payload, "metadata") || %{}
    })
  end

  # ── resource extraction ─────────────────────────────────────────────────────

  defp extract_resource("Bash", %{} = input) do
    cmd = input["command"] || input[:command]
    {:command, cmd, cmd}
  end

  defp extract_resource(tool, %{} = input) when tool in ["Edit", "Write", "NotebookEdit"] do
    path = input["file_path"] || input[:file_path] || input["notebook_path"]
    content = input["new_string"] || input["content"] || input[:content]
    {:file, path, content}
  end

  defp extract_resource("Read", %{} = input) do
    path = input["file_path"] || input[:file_path]
    {:file, path, nil}
  end

  defp extract_resource("MultiEdit", %{} = input) do
    path = input["file_path"] || input[:file_path]
    edits = input["edits"] || input[:edits] || []

    content =
      edits
      |> Enum.map(fn e -> e["new_string"] || e[:new_string] || "" end)
      |> Enum.join("\n")

    {:file, path, content}
  end

  defp extract_resource(tool, %{} = input) when tool in ["WebFetch", "WebSearch"] do
    url = input["url"] || input[:url] || input["query"] || input[:query]
    {:url, url, nil}
  end

  defp extract_resource(_, _), do: {:unknown, nil, nil}

  # ── agent_type extraction ───────────────────────────────────────────────────

  # Claude hook payloads may carry the subagent type under a few keys depending
  # on how the hook was fired. Check them in priority order and fall back to
  # "root" for top-level sessions.
  defp extract_agent_type(payload) do
    Map.get(payload, "agent_type") ||
      Map.get(payload, :agent_type) ||
      Map.get(payload, "subagent_type") ||
      Map.get(payload, :subagent_type) ||
      Map.get(payload, "agent_name") ||
      Map.get(payload, :agent_name) ||
      "root"
  end

  # ── event normalization ─────────────────────────────────────────────────────

  defp normalize_event(payload) do
    raw = Map.get(payload, "hook_event_name") || Map.get(payload, :event)

    case raw do
      "PreToolUse" -> :pre_tool_use
      "PostToolUse" -> :post_tool_use
      "Stop" -> :stop
      "UserPromptSubmit" -> :user_prompt_submit
      :pre_tool_use -> :pre_tool_use
      :post_tool_use -> :post_tool_use
      :stop -> :stop
      :user_prompt_submit -> :user_prompt_submit
      _ -> :pre_tool_use
    end
  end
end
