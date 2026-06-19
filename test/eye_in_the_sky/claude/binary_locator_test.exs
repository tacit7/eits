defmodule EyeInTheSky.Claude.BinaryLocatorTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.BinaryLocator

  # ---------------------------------------------------------------------------
  # find/0 — integration (runs on this machine, claude must be installed)
  # ---------------------------------------------------------------------------

  describe "find/0" do
    @tag :host_dependent
    test "returns {:ok, path} when claude is installed" do
      assert {:ok, path} = BinaryLocator.find()
      assert is_binary(path)
      assert String.ends_with?(path, "claude")
    end

    @tag :host_dependent
    test "returned path is an actual file" do
      {:ok, path} = BinaryLocator.find()
      assert File.exists?(path)
    end
  end

  # ---------------------------------------------------------------------------
  # semver_dir?/1
  # ---------------------------------------------------------------------------

  describe "semver_dir?/1" do
    test "valid semver directory" do
      assert BinaryLocator.semver_dir?("v20.11.0")
      assert BinaryLocator.semver_dir?("v18.0.0")
      assert BinaryLocator.semver_dir?("v22.1.3")
    end

    test "rejects non-semver strings" do
      refute BinaryLocator.semver_dir?("latest")
      refute BinaryLocator.semver_dir?("lts")
      refute BinaryLocator.semver_dir?("system")
      refute BinaryLocator.semver_dir?(".DS_Store")
    end

    test "rejects missing v prefix" do
      refute BinaryLocator.semver_dir?("20.11.0")
    end

    test "rejects partial versions" do
      refute BinaryLocator.semver_dir?("v20")
      refute BinaryLocator.semver_dir?("v20.11")
    end
  end

  # ---------------------------------------------------------------------------
  # parse_version/1
  # ---------------------------------------------------------------------------

  describe "parse_version/1" do
    test "parses valid version" do
      assert %Version{major: 20, minor: 11, patch: 0} = BinaryLocator.parse_version("v20.11.0")
    end

    test "parses another version" do
      assert %Version{major: 18, minor: 3, patch: 2} = BinaryLocator.parse_version("v18.3.2")
    end

    test "falls back to 0.0.0 for invalid version" do
      assert %Version{major: 0, minor: 0, patch: 0} = BinaryLocator.parse_version("v-bad")
    end

    test "versions sort correctly descending" do
      dirs = ["v18.0.0", "v22.1.0", "v20.11.0", "v16.0.0"]

      sorted =
        dirs
        |> Enum.filter(&BinaryLocator.semver_dir?/1)
        |> Enum.sort_by(&BinaryLocator.parse_version/1, {:desc, Version})

      assert sorted == ["v22.1.0", "v20.11.0", "v18.0.0", "v16.0.0"]
    end
  end
end
