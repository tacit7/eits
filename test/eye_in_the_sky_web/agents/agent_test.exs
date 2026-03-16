defmodule EyeInTheSkyWeb.Agents.AgentTest do
  use EyeInTheSkyWeb.DataCase, async: true

  alias EyeInTheSkyWeb.Agents
  alias EyeInTheSkyWeb.Agents.Agent

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_agent(overrides \\ %{}) do
    {:ok, agent} =
      Agents.create_agent(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            description: "Test agent",
            source: "test"
          },
          overrides
        )
      )

    agent
  end

  defp reload(agent) do
    Agents.get_agent!(agent.id)
  end

  # ---------------------------------------------------------------------------
  # Schema
  # ---------------------------------------------------------------------------

  describe "schema" do
    test "last_activity_at is typed as :string" do
      assert Agent.__schema__(:type, :last_activity_at) == :string
    end

    test "created_at, archived_at, and last_activity_at are all :string" do
      assert Agent.__schema__(:type, :created_at) == :string
      assert Agent.__schema__(:type, :archived_at) == :string
      assert Agent.__schema__(:type, :last_activity_at) == :string
    end
  end

  # ---------------------------------------------------------------------------
  # Changeset
  # ---------------------------------------------------------------------------

  describe "changeset/2" do
    test "casts last_activity_at as a string" do
      agent = %Agent{}
      ts = "2026-03-15T10:00:00Z"

      changeset = Agent.changeset(agent, %{last_activity_at: ts})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :last_activity_at) == ts
    end

    test "does not reject nil last_activity_at" do
      agent = %Agent{}
      changeset = Agent.changeset(agent, %{last_activity_at: nil})

      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Persistence
  # ---------------------------------------------------------------------------

  describe "last_activity_at DB round-trip" do
    test "stores and loads an ISO8601 string" do
      ts = "2026-03-15T12:34:56Z"
      agent = create_agent()

      {:ok, updated} = Agents.update_agent(agent, %{last_activity_at: ts})
      assert updated.last_activity_at == ts

      loaded = reload(updated)
      assert loaded.last_activity_at == ts
    end

    test "returns nil when not set" do
      agent = create_agent()
      loaded = reload(agent)
      assert is_nil(loaded.last_activity_at)
    end

    test "loaded value is always a string, never a NaiveDateTime struct" do
      ts = "2026-01-01T00:00:00Z"
      agent = create_agent()

      {:ok, _} = Agents.update_agent(agent, %{last_activity_at: ts})
      loaded = reload(agent)

      assert is_binary(loaded.last_activity_at) or is_nil(loaded.last_activity_at)
      refute match?(%NaiveDateTime{}, loaded.last_activity_at)
    end

    test "stores microsecond precision ISO8601 string intact" do
      ts = "2026-03-15T12:34:56.789123Z"
      agent = create_agent()

      {:ok, _} = Agents.update_agent(agent, %{last_activity_at: ts})
      loaded = reload(agent)

      assert loaded.last_activity_at == ts
    end
  end
end
