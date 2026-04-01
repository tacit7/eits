defmodule EyeInTheSkyWeb.Helpers.ViewHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Helpers.ViewHelpers

  describe "parse_budget/1" do
    test "returns nil for nil" do
      assert ViewHelpers.parse_budget(nil) == nil
    end

    test "returns nil for empty string" do
      assert ViewHelpers.parse_budget("") == nil
    end

    test "parses a valid positive float string" do
      assert ViewHelpers.parse_budget("1.50") == 1.5
    end

    test "parses an integer string as float" do
      assert ViewHelpers.parse_budget("10") == 10.0
    end

    test "returns nil for zero" do
      assert ViewHelpers.parse_budget("0") == nil
    end

    test "returns nil for negative value" do
      assert ViewHelpers.parse_budget("-5.0") == nil
    end

    test "returns nil for non-numeric string" do
      assert ViewHelpers.parse_budget("abc") == nil
    end

    test "parses string with trailing non-numeric chars (Float.parse behavior)" do
      # Float.parse("1.5abc") returns {1.5, "abc"} — budget accepts this
      assert ViewHelpers.parse_budget("1.5abc") == 1.5
    end
  end
end
