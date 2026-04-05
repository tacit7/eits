defmodule EyeInTheSky.Claude.SessionFileLocatorTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.SessionFileLocator

  describe "escape_project_path/1" do
    test "replaces slashes and dots with hyphens" do
      assert SessionFileLocator.escape_project_path("/Users/user/projects/myapp") ==
               "-Users-user-projects-myapp"
    end

    test "handles root path" do
      assert SessionFileLocator.escape_project_path("/") == "-"
    end

    test "handles path without leading slash" do
      assert SessionFileLocator.escape_project_path("relative/path") == "relative-path"
    end

    test "replaces dots with hyphens" do
      assert SessionFileLocator.escape_project_path("/Users/user/.config") ==
               "-Users-user--config"
    end
  end

  describe "locate/2" do
    test "returns {:error, :not_found} for nonexistent session" do
      assert {:error, :not_found} =
               SessionFileLocator.locate("nonexistent-uuid", "/tmp/no-such-project")
    end

    test "returns {:ok, path} when file exists" do
      home = System.get_env("HOME")
      dir = Path.join([home, ".claude", "projects", "-tmp-locator-test"])
      File.mkdir_p!(dir)
      file = Path.join(dir, "test-session.jsonl")
      File.write!(file, "{}\n")

      assert {:ok, ^file} = SessionFileLocator.locate("test-session", "/tmp/locator-test")
    after
      home = System.get_env("HOME")
      dir = Path.join([home, ".claude", "projects", "-tmp-locator-test"])
      File.rm_rf!(dir)
    end
  end

  describe "locate_by_id/2" do
    test "builds path using raw project_id as directory name" do
      home = System.get_env("HOME")
      expected = Path.join([home, ".claude", "projects", "my-project", "abc-123.jsonl"])
      assert SessionFileLocator.locate_by_id("my-project", "abc-123") == expected
    end
  end

  describe "exists?/2" do
    test "returns false for nonexistent session" do
      refute SessionFileLocator.exists?("nonexistent-uuid", "/tmp/no-such-project")
    end

    test "returns true when file exists" do
      home = System.get_env("HOME")
      dir = Path.join([home, ".claude", "projects", "-tmp-locator-exists-test"])
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "exists-session.jsonl"), "{}\n")

      assert SessionFileLocator.exists?("exists-session", "/tmp/locator-exists-test")
    after
      home = System.get_env("HOME")
      dir = Path.join([home, ".claude", "projects", "-tmp-locator-exists-test"])
      File.rm_rf!(dir)
    end
  end
end
