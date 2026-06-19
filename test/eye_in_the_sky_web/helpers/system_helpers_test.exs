defmodule EyeInTheSkyWeb.Helpers.SystemHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Helpers.SystemHelpers

  describe "open_in_system/1" do
    test "accepts a binary path and returns a tuple" do
      # We cannot assert on the exit code because the file may not exist,
      # but the function must return the {stdout, exit_code} tuple that
      # System.cmd/3 always produces.
      result = SystemHelpers.open_in_system("/tmp/eits_system_helpers_test_dummy_path")
      assert is_tuple(result)
      assert tuple_size(result) == 2
      {output, status} = result
      assert is_binary(output)
      assert is_integer(status)
    end

    test "returns non-zero exit code for a path that does not exist" do
      {_output, status} =
        SystemHelpers.open_in_system(
          "/tmp/eits_nonexistent_#{System.unique_integer([:positive])}"
        )

      # On macOS `open` returns 1 for missing paths; on Linux `xdg-open` may
      # return 2 or 4. Either way it must be non-zero.
      assert status != 0
    end

    test "accepts an empty string path without raising" do
      result = SystemHelpers.open_in_system("")
      assert is_tuple(result)
    end
  end
end
