defmodule EyeInTheSky.IAM.HookResponse do
  @moduledoc """
  Converts an `EyeInTheSky.IAM.Decision` into the JSON shape expected by the
  Claude Code hook protocol.

  ## Hook response shapes by permutation

  ### PreToolUse — deny

      %{
        "hookSpecificOutput" => %{
          "hookEventName" => "PreToolUse",
          "permissionDecision" => "deny",
          "permissionDecisionReason" => "<reason>"
        }
      }

  ### PreToolUse — allow, with instructions

      %{
        "continue" => true,
        "hookSpecificOutput" => %{
          "hookEventName" => "PreToolUse",
          "permissionDecision" => "allow",
          "additionalContext" => "<rendered markdown>"
        }
      }

  ### PreToolUse — allow, no instructions

      %{"continue" => true, "hookSpecificOutput" => %{"hookEventName" => "PreToolUse", "permissionDecision" => "allow"}}

  ### Non-PreToolUse (PostToolUse, Stop) — deny

      %{"continue" => false, "stopReason" => "<reason>"}

  ### Non-PreToolUse — allow, with instructions

      %{
        "continue" => true,
        "suppressOutput" => true,
        "hookSpecificOutput" => %{
          "hookEventName" => "<event>",
          "additionalContext" => "<rendered markdown>"
        }
      }

  ### Non-PreToolUse — allow, no instructions

      %{"continue" => true}
  """

  alias EyeInTheSky.IAM.Decision

  @type event :: :pre_tool_use | :post_tool_use | :stop | :user_prompt_submit
  @type hook_json :: map()

  @doc "Build the hook JSON response for the given decision and hook event."
  @spec from_decision(Decision.t(), event()) :: hook_json()
  def from_decision(%Decision{permission: :deny} = d, :pre_tool_use) do
    %{
      "hookSpecificOutput" => %{
        "hookEventName" => "PreToolUse",
        "permissionDecision" => "deny",
        "permissionDecisionReason" => d.reason || "Denied by IAM policy"
      }
    }
  end

  def from_decision(%Decision{permission: :deny} = d, _event) do
    %{
      "continue" => false,
      "stopReason" => d.reason || "Denied by IAM policy"
    }
  end

  def from_decision(%Decision{permission: :allow, instructions: []} = _d, :pre_tool_use) do
    %{
      "continue" => true,
      "hookSpecificOutput" => %{
        "hookEventName" => "PreToolUse",
        "permissionDecision" => "allow"
      }
    }
  end

  def from_decision(%Decision{permission: :allow, instructions: instructions} = _d, :pre_tool_use)
      when instructions != [] do
    %{
      "continue" => true,
      "hookSpecificOutput" => %{
        "hookEventName" => "PreToolUse",
        "permissionDecision" => "allow",
        "additionalContext" => render_instructions(instructions)
      }
    }
  end

  def from_decision(%Decision{permission: :allow, instructions: []}, event) do
    _ = event
    %{"continue" => true}
  end

  def from_decision(
        %Decision{permission: :allow, instructions: instructions},
        :user_prompt_submit
      )
      when instructions != [] do
    %{
      "suppressUserPrompt" => true,
      "hookSpecificOutput" => %{
        "hookEventName" => "UserPromptSubmit",
        "userPrompt" => hd(instructions).message
      }
    }
  end

  def from_decision(%Decision{permission: :allow, instructions: instructions}, event)
      when instructions != [] do
    %{
      "continue" => true,
      "suppressOutput" => true,
      "hookSpecificOutput" => %{
        "hookEventName" => event_name(event),
        "additionalContext" => render_instructions(instructions)
      }
    }
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  defp render_instructions(instructions) do
    instructions
    |> Enum.map(fn %{policy: policy, message: msg} ->
      "**#{policy.name}**: #{msg}"
    end)
    |> Enum.join("\n\n")
  end

  defp event_name(:pre_tool_use), do: "PreToolUse"
  defp event_name(:post_tool_use), do: "PostToolUse"
  defp event_name(:stop), do: "Stop"
  defp event_name(:user_prompt_submit), do: "UserPromptSubmit"
  defp event_name(_), do: "Unknown"
end
