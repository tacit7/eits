defmodule EyeInTheSkyWeb.ControllerHelpersTest do
  use ExUnit.Case, async: true

  import EyeInTheSkyWeb.ControllerHelpers

  describe "parse_starred/1" do
    test "nil returns nil" do
      assert parse_starred(nil) == nil
    end

    test "true returns true" do
      assert parse_starred(true) == true
    end

    test "false returns false" do
      assert parse_starred(false) == false
    end

    test "integer 1 returns true" do
      assert parse_starred(1) == true
    end

    test "integer 0 returns false" do
      assert parse_starred(0) == false
    end

    test "non-zero integer returns true (no FunctionClauseError)" do
      assert parse_starred(2) == true
      assert parse_starred(-1) == true
      assert parse_starred(99) == true
    end

    test "string '1' returns true" do
      assert parse_starred("1") == true
    end

    test "string 'true' returns true" do
      assert parse_starred("true") == true
    end

    test "string '0' returns false" do
      assert parse_starred("0") == false
    end

    test "string 'false' returns false" do
      assert parse_starred("false") == false
    end

    test "unrecognized string returns nil" do
      assert parse_starred("yes") == nil
      assert parse_starred("") == nil
      assert parse_starred("2") == nil
    end
  end
end
