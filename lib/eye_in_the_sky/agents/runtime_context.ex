defmodule EyeInTheSky.Agents.RuntimeContext do
  @moduledoc """
  Builds the runtime context map passed to AgentWorker on each message dispatch.

  Centralizes context construction and the `has_messages` derivation so that
  `AgentManager.send_message/3` only has to: resolve the worker → build context
  → call the worker.

  ## Fields

  - `:model` — LLM model string (e.g. "claude-3-5-sonnet")
  - `:effort_level` — effort/reasoning level hint for the provider
  - `:has_messages` — whether the session has prior inbound replies; controls
    whether the SDK resumes an existing conversation or starts fresh
  - `:channel_id` — optional DM/chat channel to echo the result to
  - `:thinking_budget` — extended thinking token budget (Claude only)
  - `:max_budget_usd` — USD cap for the run
  - `:agent` — agent identifier forwarded to CLI flags
  - `:eits_workflow` — EITS workflow identifier string (default: "1")
  - `:bypass_sandbox` — skip all confirmations and sandboxing (Codex only; maps to --dangerously-bypass-approvals-and-sandbox)
  - `:message_id` — DB id of the outbound message record tracking this job's lifecycle
  """

  alias EyeInTheSky.Claude.ModelCapabilities
  alias EyeInTheSky.Messages

  @known_keys ~w(model effort_level channel_id thinking_budget max_budget_usd agent eits_workflow bypass_sandbox content_blocks message_id dm_metadata)a

  @type t :: %{
          model: String.t() | nil,
          effort_level: String.t() | nil,
          has_messages: boolean(),
          channel_id: integer() | nil,
          thinking_budget: integer() | nil,
          max_budget_usd: float() | nil,
          agent: String.t() | nil,
          eits_workflow: String.t(),
          bypass_sandbox: boolean(),
          content_blocks: [EyeInTheSky.Claude.ContentBlock.t()],
          message_id: integer() | nil,
          dm_metadata: map() | nil,
          extra_cli_opts: keyword()
        }

  @doc """
  Builds a runtime context map for the given session and opts.

  Queries `Messages.has_inbound_reply?/2` to determine whether the session
  has prior conversation history, which controls SDK resume vs. fresh start.

  Any opts not in the known set are forwarded as `:extra_cli_opts` so they
  reach `CLI.build_args` for flags like `--add-dir`, `--mcp-config`, etc.
  """
  @spec build(session_id :: integer(), provider :: String.t(), opts :: keyword()) :: t()
  def build(session_id, provider, opts) do
    extra = Keyword.drop(opts, @known_keys)

    %{
      model: opts[:model],
      effort_level: opts[:effort_level],
      has_messages: Messages.has_inbound_reply?(session_id, provider),
      channel_id: opts[:channel_id],
      thinking_budget: opts[:thinking_budget],
      max_budget_usd: opts[:max_budget_usd],
      agent: opts[:agent],
      eits_workflow: opts[:eits_workflow],
      bypass_sandbox: opts[:bypass_sandbox] || provider == "codex",
      content_blocks: ModelCapabilities.filter_blocks(opts[:content_blocks] || [], opts[:model]),
      message_id: opts[:message_id],
      dm_metadata: opts[:dm_metadata],
      extra_cli_opts: extra
    }
  end
end
