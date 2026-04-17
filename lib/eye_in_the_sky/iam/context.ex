defmodule EyeInTheSky.IAM.Context do
  @moduledoc """
  Normalized hook-event input for the IAM evaluator.

  Produced by `EyeInTheSky.IAM.Normalizer` from raw Claude Code hook payloads.
  The evaluator takes this struct exclusively; it does not know Claude's wire
  format.

  Field semantics:

    * `:project_id` — canonical project identity, resolved from the session if
      possible. Preferred by the evaluator for project-scoped matching.
    * `:project_path` — canonicalized absolute filesystem path. Fallback-grade
      only; used when `:project_id` cannot be resolved or for cross-project
      path-glob rules.
    * `:agent_type` — Claude subagent name from the payload. Top-level sessions
      use `"root"`.
    * `:resource_type` — normalized kind of the primary resource targeted by
      the tool call. `:command` for Bash, `:file` for Edit/Write, `:url` for
      network tools, `:unknown` for anything else.
    * `:resource_path` — the path-like identifier for the resource (file path,
      URL, etc.). Used for `resource_glob` matching in user policies.
    * `:resource_content` — the textual payload (command string, file
      contents). Used by built-in content-aware policies; not exposed to
      user-authored policies in v1.
  """

  @type event :: :pre_tool_use | :post_tool_use | :stop
  @type resource_type :: :command | :file | :url | :unknown

  @type t :: %__MODULE__{
          event: event(),
          agent_type: String.t(),
          project_id: integer() | nil,
          project_path: String.t() | nil,
          tool: String.t() | nil,
          resource_type: resource_type(),
          resource_path: String.t() | nil,
          resource_content: String.t() | nil,
          raw_tool_input: map(),
          session_uuid: String.t() | nil,
          metadata: map()
        }

  defstruct event: nil,
            agent_type: "root",
            project_id: nil,
            project_path: nil,
            tool: nil,
            resource_type: :unknown,
            resource_path: nil,
            resource_content: nil,
            raw_tool_input: %{},
            session_uuid: nil,
            metadata: %{}

  @doc "Build a context struct from a map of fields. Unknown keys are ignored."
  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    struct(__MODULE__, attrs)
  end
end
