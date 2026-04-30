defmodule EyeInTheSky.Agents.InstructionTemplates do
  @moduledoc """
  Reusable instruction text fragments injected into spawned agent prompts.
  Centralising them here ensures CLI syntax and workflow steps stay consistent
  across all places that build agent instructions.
  """

  @doc """
  Returns the team context block injected into every team-member agent's
  instructions.  The output is byte-for-byte identical to the inline heredoc
  that previously lived in `AgentManager.build_team_context/2`.
  """
  def team_context(team, member_name) do
    """
    ## Team Context
    You are member "#{member_name || "agent"}" of team "#{team.name}" (team_id: #{team.id}).
    You have been registered as a team member automatically.

    ## EITS Command Protocol

    Use the eits CLI script for all EITS operations:

      eits tasks begin --title "<title>"
      eits tasks complete <id> --message "..."
      eits dm --to <session_uuid> --message "..."
      eits commits create --hash <hash>

    ## Task Completion
    When you finish a task, follow this sequence exactly:
    1. Close the task with: eits tasks complete <id> --message "What was done"
       (atomic: annotates + marks done in one round-trip)
       If complete fails, fall back to: eits tasks annotate <id> --body "..." && eits tasks update <id> --state done
    2. DM the orchestrator session to report completion
    3. Run the `/i-update-status` slash command to commit work and update session tracking
    Do NOT skip any steps. The orchestrator needs to see what you did.
    """
  end
end
