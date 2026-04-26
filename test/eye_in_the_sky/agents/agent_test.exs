defmodule EyeInTheSky.Agents.AgentTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Agents
  alias EyeInTheSky.Agents.Agent

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
    test "last_activity_at is typed as :utc_datetime_usec" do
      assert Agent.__schema__(:type, :last_activity_at) == :utc_datetime_usec
    end

    test "created_at, archived_at, and last_activity_at are all :utc_datetime_usec" do
      assert Agent.__schema__(:type, :created_at) == :utc_datetime_usec
      assert Agent.__schema__(:type, :archived_at) == :utc_datetime_usec
      assert Agent.__schema__(:type, :last_activity_at) == :utc_datetime_usec
    end
  end

  # ---------------------------------------------------------------------------
  # Changeset
  # ---------------------------------------------------------------------------

  describe "changeset/2" do
    test "casts last_activity_at from ISO8601 string to DateTime" do
      agent = %Agent{}
      ts = "2026-03-15T10:00:00Z"

      changeset = Agent.changeset(agent, %{last_activity_at: ts})

      assert changeset.valid?
      cast_value = Ecto.Changeset.get_change(changeset, :last_activity_at)
      assert %DateTime{} = cast_value
      assert cast_value.year == 2026
      assert cast_value.month == 3
      assert cast_value.day == 15
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
    test "stores and loads a DateTime value" do
      ts = ~U[2026-03-15 12:34:56.000000Z]
      agent = create_agent()

      {:ok, updated} = Agents.update_agent(agent, %{last_activity_at: ts})
      assert %DateTime{} = updated.last_activity_at

      loaded = reload(updated)
      assert %DateTime{} = loaded.last_activity_at
      assert DateTime.compare(loaded.last_activity_at, ts) == :eq
    end

    test "returns nil when not set" do
      agent = create_agent()
      loaded = reload(agent)
      assert is_nil(loaded.last_activity_at)
    end

    test "loaded value is always a DateTime struct, never a string" do
      ts = ~U[2026-01-01 00:00:00.000000Z]
      agent = create_agent()

      {:ok, _} = Agents.update_agent(agent, %{last_activity_at: ts})
      loaded = reload(agent)

      assert %DateTime{} = loaded.last_activity_at
      refute is_binary(loaded.last_activity_at)
    end

    test "stores microsecond precision intact" do
      ts = ~U[2026-03-15 12:34:56.789123Z]
      agent = create_agent()

      {:ok, _} = Agents.update_agent(agent, %{last_activity_at: ts})
      loaded = reload(agent)

      assert %DateTime{} = loaded.last_activity_at
      assert DateTime.compare(loaded.last_activity_at, ts) == :eq
    end
  end
end
