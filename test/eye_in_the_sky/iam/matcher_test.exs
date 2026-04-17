defmodule EyeInTheSky.IAM.MatcherTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Matcher

  describe "match_glob?/2" do
    test "nil pattern matches anything" do
      assert Matcher.match_glob?("/any/path", nil)
      assert Matcher.match_glob?(nil, nil)
    end

    test "wildcard-only matches anything non-nil" do
      assert Matcher.match_glob?("anything", "*")
      assert Matcher.match_glob?("", "*")
    end

    test "literal match" do
      assert Matcher.match_glob?("/foo/bar", "/foo/bar")
      refute Matcher.match_glob?("/foo/baz", "/foo/bar")
    end

    test "star matches across separators" do
      assert Matcher.match_glob?("/a/b/c/file.ex", "/a/*/file.ex")
      assert Matcher.match_glob?("/a/b/c", "/a/*")
    end

    test "question mark matches single char" do
      assert Matcher.match_glob?("cat", "c?t")
      refute Matcher.match_glob?("caat", "c?t")
    end

    test "character class" do
      assert Matcher.match_glob?("a", "[abc]")
      assert Matcher.match_glob?("c", "[abc]")
      refute Matcher.match_glob?("d", "[abc]")
    end

    test "special regex chars in pattern are escaped" do
      assert Matcher.match_glob?("/foo.bar", "/foo.bar")
      refute Matcher.match_glob?("/fooxbar", "/foo.bar")
    end

    test "nil value matches only wildcard or nil pattern" do
      assert Matcher.match_glob?(nil, "*")
      refute Matcher.match_glob?(nil, "/foo")
    end
  end
end
