defmodule EyeInTheSky.Utils.ToolHelpersTest do
  use EyeInTheSky.DataCase, async: false

  import EyeInTheSky.Factory

  alias EyeInTheSky.Utils.ToolHelpers

  describe "resolve_session_int_id/1" do
    test "returns error for nil" do
      assert {:error, _} = ToolHelpers.resolve_session_int_id(nil)
    end

    test "returns error for integer id that does not exist" do
      assert {:error, "Session not found: 999999999"} =
               ToolHelpers.resolve_session_int_id(999_999_999)
    end

    test "returns {:ok, id} for integer id that exists" do
      session = new_session()
      id = session.id
      assert {:ok, ^id} = ToolHelpers.resolve_session_int_id(session.id)
    end

    test "returns error for string numeric id that does not exist" do
      assert {:error, "Session not found: 999999999"} =
               ToolHelpers.resolve_session_int_id("999999999")
    end

    test "returns {:ok, id} for string numeric id that exists" do
      session = new_session()
      id = session.id
      assert {:ok, ^id} = ToolHelpers.resolve_session_int_id(to_string(session.id))
    end

    test "returns {:ok, id} for valid uuid" do
      session = new_session()
      id = session.id
      assert {:ok, ^id} = ToolHelpers.resolve_session_int_id(session.uuid)
    end

    test "returns error for unknown uuid" do
      assert {:error, "Session not found: " <> _} =
               ToolHelpers.resolve_session_int_id(Ecto.UUID.generate())
    end
  end
end
