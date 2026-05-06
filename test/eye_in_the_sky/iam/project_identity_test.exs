defmodule EyeInTheSky.IAM.ProjectIdentityTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.ProjectIdentity

  describe "canonicalize/1" do
    test "returns nil for nil" do
      assert ProjectIdentity.canonicalize(nil) == nil
    end

    test "returns nil for empty string" do
      assert ProjectIdentity.canonicalize("") == nil
    end

    test "returns nil for non-strings" do
      assert ProjectIdentity.canonicalize(:foo) == nil
      assert ProjectIdentity.canonicalize(42) == nil
    end

    test "expands relative paths to absolute" do
      result = ProjectIdentity.canonicalize(".")
      assert String.starts_with?(result, "/")
    end

    test "strips trailing slash" do
      # Use a synthesized non-symlinked path so we don't trigger
      # final-segment symlink resolution (/tmp is a symlink on macOS).
      assert ProjectIdentity.canonicalize("/nonexistent/foo/") == "/nonexistent/foo"
    end

    test "preserves root slash" do
      assert ProjectIdentity.canonicalize("/") == "/"
    end

    test "normalizes backslashes to forward slashes" do
      assert ProjectIdentity.canonicalize("/tmp\\foo") == "/tmp/foo"
    end

    test "preserves case (documented limitation on case-insensitive FS)" do
      assert ProjectIdentity.canonicalize("/Users/Foo") == "/Users/Foo"
    end

    test "resolves a final-segment symlink once" do
      # Create a tmp dir with a symlink pointing at an existing path, then
      # canonicalize the symlink and assert we get the target.
      tmp = System.tmp_dir!()
      target = Path.join(tmp, "iam_test_target_#{System.unique_integer([:positive])}")
      link = Path.join(tmp, "iam_test_link_#{System.unique_integer([:positive])}")

      File.mkdir_p!(target)

      on_exit(fn ->
        File.rm_rf(target)
        File.rm(link)
      end)

      :ok = File.ln_s(target, link)

      assert ProjectIdentity.canonicalize(link) == target
    end
  end
end
