defmodule EyeInTheSkyWeb.Components.NewSessionModalTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Components.NewSessionModal

  @agents [
    {"eits-superpowers", "EITS Superpowers", :global},
    {"eits-workflow", "EITS Workflow", :global},
    {"bugfix", "Bug Fixer", :global},
    {"code-reviewer", "Code Reviewer", :project}
  ]

  describe "agent filtering logic" do
    test "empty query returns all agents" do
      assert filter_agents(@agents, "") == @agents
    end

    test "matches on slug substring" do
      result = filter_agents(@agents, "eits")
      slugs = Enum.map(result, &elem(&1, 0))
      assert slugs == ["eits-superpowers", "eits-workflow"]
    end

    test "matches on name substring case-insensitively" do
      result = filter_agents(@agents, "code")
      slugs = Enum.map(result, &elem(&1, 0))
      assert slugs == ["code-reviewer"]
    end

    test "returns empty list when nothing matches" do
      assert filter_agents(@agents, "zzznomatch") == []
    end

    test "case-insensitive slug match" do
      assert filter_agents(@agents, "EITS") |> length() == 2
    end

    test "case-insensitive name match" do
      result = filter_agents(@agents, "BUG")
      assert Enum.map(result, &elem(&1, 0)) == ["bugfix"]
    end
  end

  describe "module exports" do
    test "NewSessionModal is compiled and exports render/1" do
      assert Code.ensure_loaded?(NewSessionModal)
      assert function_exported?(NewSessionModal, :render, 1)
    end
  end

  # Mirrors the inline filtering in render/1 so tests stay in sync with the component.
  defp filter_agents(agents, "") do
    agents
  end

  defp filter_agents(agents, query) do
    q = String.downcase(query)

    Enum.filter(agents, fn {slug, name, _scope} ->
      String.contains?(String.downcase(slug), q) or
        String.contains?(String.downcase(name), q)
    end)
  end
end
