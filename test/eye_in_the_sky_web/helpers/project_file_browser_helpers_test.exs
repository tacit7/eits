defmodule EyeInTheSkyWeb.Helpers.ProjectFileBrowserHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Helpers.ProjectFileBrowserHelpers

  describe "path_within?/2" do
    test "exact base match is allowed" do
      assert ProjectFileBrowserHelpers.path_within?("/project/app", "/project/app")
    end

    test "valid child path is allowed" do
      assert ProjectFileBrowserHelpers.path_within?("/project/app/src/foo.ex", "/project/app")
    end

    test "direct child is allowed" do
      assert ProjectFileBrowserHelpers.path_within?("/project/app/file.txt", "/project/app")
    end

    test "sibling-prefix path is rejected" do
      refute ProjectFileBrowserHelpers.path_within?("/project/app-evil", "/project/app")
    end

    test "sibling with similar prefix is rejected" do
      refute ProjectFileBrowserHelpers.path_within?("/project/application", "/project/app")
    end

    test "parent directory is rejected" do
      refute ProjectFileBrowserHelpers.path_within?("/project", "/project/app")
    end

    test "unrelated path is rejected" do
      refute ProjectFileBrowserHelpers.path_within?("/etc/passwd", "/project/app")
    end

    test "relative traversal attempt is rejected" do
      refute ProjectFileBrowserHelpers.path_within?("/project/app/../etc/passwd", "/project/app")
    end
  end
end
