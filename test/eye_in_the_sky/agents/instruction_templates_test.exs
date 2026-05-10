defmodule EyeInTheSky.Agents.InstructionTemplatesTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Agents.InstructionTemplates

  defp team(overrides \\ %{}) do
    Map.merge(%{id: 42, name: "my-team"}, overrides)
  end

  describe "team_context/2" do
    test "includes the team name in the output" do
      result = InstructionTemplates.team_context(team(%{name: "alpha-squad"}), "bot-1")
      assert result =~ ~s|team "alpha-squad"|
    end

    test "includes the team id in the output" do
      result = InstructionTemplates.team_context(team(%{id: 99}), "bot-1")
      assert result =~ "team_id: 99"
    end

    test "includes the member name in the output" do
      result = InstructionTemplates.team_context(team(), "worker-7")
      assert result =~ ~s|member "worker-7"|
    end

    test "falls back to 'agent' when member_name is nil" do
      result = InstructionTemplates.team_context(team(), nil)
      assert result =~ ~s|member "agent"|
    end

    test "contains the Team Context section header" do
      result = InstructionTemplates.team_context(team(), "x")
      assert result =~ "## Team Context"
    end

    test "contains the EITS Command Protocol section header" do
      result = InstructionTemplates.team_context(team(), "x")
      assert result =~ "## EITS Command Protocol"
    end

    test "contains the Task Completion section header" do
      result = InstructionTemplates.team_context(team(), "x")
      assert result =~ "## Task Completion"
    end

    test "includes eits tasks begin command" do
      result = InstructionTemplates.team_context(team(), "x")
      assert result =~ "eits tasks begin"
    end

    test "includes eits tasks complete command" do
      result = InstructionTemplates.team_context(team(), "x")
      assert result =~ "eits tasks complete"
    end

    test "includes eits dm command" do
      result = InstructionTemplates.team_context(team(), "x")
      assert result =~ "eits dm --to"
    end

    test "includes eits commits create command" do
      result = InstructionTemplates.team_context(team(), "x")
      assert result =~ "eits commits create --hash"
    end

    test "mentions the orchestrator DM step" do
      result = InstructionTemplates.team_context(team(), "x")
      assert result =~ "DM the orchestrator"
    end

    test "mentions i-update-status slash command" do
      result = InstructionTemplates.team_context(team(), "x")
      assert result =~ "/i-update-status"
    end

    test "returns a string" do
      result = InstructionTemplates.team_context(team(), "x")
      assert is_binary(result)
    end

    test "member name and team name both appear when both are non-nil" do
      result = InstructionTemplates.team_context(team(%{name: "delta", id: 7}), "opus")
      assert result =~ ~s|member "opus"|
      assert result =~ ~s|team "delta"|
      assert result =~ "team_id: 7"
    end

    test "member name is empty string — uses empty string (not 'agent' fallback)" do
      result = InstructionTemplates.team_context(team(), "")
      # "" is truthy in Elixir; nil fallback does not kick in
      assert result =~ ~s|member ""|
    end
  end
end
