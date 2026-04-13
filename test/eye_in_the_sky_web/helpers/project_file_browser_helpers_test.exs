defmodule EyeInTheSkyWeb.Helpers.ProjectFileBrowserHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Helpers.ProjectFileBrowserHelpers

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp tmp_dir do
    path = Path.join(System.tmp_dir!(), "pfbh_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end

  # ---------------------------------------------------------------------------
  # path_within?/2
  # ---------------------------------------------------------------------------

  describe "path_within?/2" do
    test "returns true for a file directly inside the base" do
      base = tmp_dir()
      target = Path.join(base, "file.txt")
      File.write!(target, "ok")
      assert ProjectFileBrowserHelpers.path_within?(target, base)
    end

    test "returns true for a nested file inside the base" do
      base = tmp_dir()
      nested = Path.join(base, "a/b/c.txt")
      File.mkdir_p!(Path.dirname(nested))
      File.write!(nested, "ok")
      assert ProjectFileBrowserHelpers.path_within?(nested, base)
    end

    test "returns false for a path outside the base" do
      base = tmp_dir()
      outside = tmp_dir()
      target = Path.join(outside, "secret.txt")
      File.write!(target, "secret")
      refute ProjectFileBrowserHelpers.path_within?(target, base)
    end

    test "rejects a symlink that escapes the base directory" do
      base = tmp_dir()
      outside = tmp_dir()
      secret = Path.join(outside, "secret.txt")
      File.write!(secret, "secret content")

      link = Path.join(base, "escape_link.txt")
      File.ln_s!(secret, link)

      # Even though the link itself is inside base, its target is outside.
      refute ProjectFileBrowserHelpers.path_within?(link, base)
    end

    test "rejects a path traversal that escapes via sibling directory name prefix" do
      # Guards against the prefix collision: base=/tmp/foo, sibling=/tmp/foobar.
      # Old Path.expand-only check would allow /tmp/foobar since it starts_with?
      # "/tmp/foo" without the trailing-slash guard.
      base = tmp_dir()
      # Construct a sibling whose name shares the base's prefix.
      sibling = base <> "_ext"
      File.mkdir_p!(sibling)
      outside_file = Path.join(sibling, "target.txt")
      File.write!(outside_file, "should not be accessible")

      refute ProjectFileBrowserHelpers.path_within?(outside_file, base)
    end

    test "returns true when path equals base_dir (root directory navigation)" do
      # Path.dirname of a top-level file (e.g. "hello.ex") returns ".".
      # The Back link then navigates to ?path=. which resolves to the project
      # root itself. path_within?(root, root) must be true so the listing loads.
      base = tmp_dir()
      assert ProjectFileBrowserHelpers.path_within?(base, base)
    end

    test "returns false when base path does not exist" do
      fake_base = "/tmp/no_such_base_#{System.unique_integer([:positive])}"
      target = Path.join(fake_base, "file.txt")
      refute ProjectFileBrowserHelpers.path_within?(target, fake_base)
    end
  end

  # ---------------------------------------------------------------------------
  # resolve_list_target/2
  # ---------------------------------------------------------------------------

  describe "resolve_list_target/2" do
    test "returns {:ok, base_dir, nil} when path is nil" do
      base = tmp_dir()
      assert {:ok, ^base, nil} = ProjectFileBrowserHelpers.resolve_list_target(nil, base)
    end

    test "returns {:ok, base_dir, nil} when path is empty string" do
      base = tmp_dir()
      assert {:ok, ^base, nil} = ProjectFileBrowserHelpers.resolve_list_target("", base)
    end

    test "returns {:ok, full_path, rel_path} for a valid relative path" do
      base = tmp_dir()
      subdir = Path.join(base, "sub")
      File.mkdir_p!(subdir)

      assert {:ok, ^subdir, "sub"} =
               ProjectFileBrowserHelpers.resolve_list_target("sub", base)
    end

    test "returns {:error, 'Access denied'} for a path traversal attempt" do
      base = tmp_dir()
      outside = tmp_dir()
      _secret = File.write!(Path.join(outside, "secret.txt"), "secret")

      # ../secret.txt would resolve outside base
      assert {:error, "Access denied"} =
               ProjectFileBrowserHelpers.resolve_list_target("../secret.txt", base)
    end

    test "returns {:error, 'Access denied'} for a symlink escape" do
      base = tmp_dir()
      outside = tmp_dir()
      secret = Path.join(outside, "secret.txt")
      File.write!(secret, "secret")

      link_name = "escape_link.txt"
      File.ln_s!(secret, Path.join(base, link_name))

      assert {:error, "Access denied"} =
               ProjectFileBrowserHelpers.resolve_list_target(link_name, base)
    end
  end
end
