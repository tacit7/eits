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
  """

  alias EyeInTheSky.Messages

  @type t :: %{
          model: String.t() | nil,
          effort_level: String.t() | nil,
          has_messages: boolean(),
          channel_id: integer() | nil,
          thinking_budget: integer() | nil,
          max_budget_usd: float() | nil,
          agent: String.t() | nil,
          eits_workflow: String.t(),
          bypass_sandbox: boolean()
        }

  @doc """
  Builds a runtime context map for the given session and opts.

  Queries `Messages.has_inbound_reply?/2` to determine whether the session
  has prior conversation history, which controls SDK resume vs. fresh start.
  """
  @spec build(session_id :: integer(), provider :: String.t(), opts :: keyword()) :: t()
  def build(session_id, provider, opts) do
    %{
      model: opts[:model],
      effort_level: opts[:effort_level],
      has_messages: Messages.has_inbound_reply?(session_id, provider),
      channel_id: opts[:channel_id],
      thinking_budget: opts[:thinking_budget],
      max_budget_usd: opts[:max_budget_usd],
      agent: opts[:agent],
      eits_workflow: opts[:eits_workflow],
      bypass_sandbox: opts[:bypass_sandbox] || false
    }
  end
end
