defmodule EyeInTheSkyWeb.ControllerHelpersTest do
  use ExUnit.Case, async: true

  import EyeInTheSkyWeb.ControllerHelpers

  describe "parse_starred/1" do
    test "nil returns :error" do
      assert parse_starred(nil) == :error
    end

    test "true returns {:ok, true}" do
      assert parse_starred(true) == {:ok, true}
    end

    test "false returns {:ok, false}" do
      assert parse_starred(false) == {:ok, false}
    end

    test "integer 1 returns {:ok, true}" do
      assert parse_starred(1) == {:ok, true}
    end

    test "integer 0 returns {:ok, false}" do
      assert parse_starred(0) == {:ok, false}
    end

    test "non-zero integer returns {:ok, true}" do
      assert parse_starred(2) == {:ok, true}
      assert parse_starred(-1) == {:ok, true}
      assert parse_starred(99) == {:ok, true}
    end

    test "string '1' returns {:ok, true}" do
      assert parse_starred("1") == {:ok, true}
    end

    test "string 'true' returns {:ok, true}" do
      assert parse_starred("true") == {:ok, true}
    end

    test "string '0' returns {:ok, false}" do
      assert parse_starred("0") == {:ok, false}
    end

    test "string 'false' returns {:ok, false}" do
      assert parse_starred("false") == {:ok, false}
    end

    test "unrecognized string returns :error" do
      assert parse_starred("yes") == :error
      assert parse_starred("") == :error
      assert parse_starred("2") == :error
    end
  end
end
