defmodule EyeInTheSky.Messages.IndexHealthTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Messages.IndexHealth

  describe "list_message_indexes/0" do
    test "returns a non-empty list of indexes with valid and ready booleans" do
      assert {:ok, indexes} = IndexHealth.list_message_indexes()
      assert length(indexes) > 0

      for index <- indexes do
        assert is_binary(index.name)
        assert is_boolean(index.valid)
        assert is_boolean(index.ready)
      end
    end

    test "includes the source_uuid unique index" do
      {:ok, indexes} = IndexHealth.list_message_indexes()
      names = Enum.map(indexes, & &1.name)
      assert Enum.any?(names, &String.contains?(&1, "source_uuid"))
    end
  end

  describe "invalid_indexes/0" do
    test "returns empty list on a healthy schema" do
      assert IndexHealth.invalid_indexes() == []
    end
  end
end
