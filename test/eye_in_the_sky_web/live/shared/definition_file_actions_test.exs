defmodule EyeInTheSkyWeb.Live.Shared.DefinitionFileActionsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Live.Shared.DefinitionFileActions

  @moduletag :tmp_dir

  describe "duplicate_file/1" do
    test "copies content into <name>-copy<ext>", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "reviewer.md")
      File.write!(path, "---\nname: reviewer\n---\nBody")

      assert {:ok, new_path} = DefinitionFileActions.duplicate_file(path)

      assert new_path == Path.join(tmp_dir, "reviewer-copy.md")
      assert File.read!(new_path) == "---\nname: reviewer\n---\nBody"
      assert File.exists?(path)
    end

    test "increments the suffix when -copy already exists", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "a.md")
      File.write!(path, "x")
      File.write!(Path.join(tmp_dir, "a-copy.md"), "existing")

      assert {:ok, new_path} = DefinitionFileActions.duplicate_file(path)
      assert new_path == Path.join(tmp_dir, "a-copy-2.md")
    end

    test "returns an error tuple when the source file doesn't exist", %{tmp_dir: tmp_dir} do
      assert {:error, :enoent} =
               DefinitionFileActions.duplicate_file(Path.join(tmp_dir, "missing.md"))
    end
  end

  describe "delete_file/1" do
    test "removes the file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "gone.md")
      File.write!(path, "x")

      assert :ok = DefinitionFileActions.delete_file(path)
      refute File.exists?(path)
    end

    test "returns an error tuple for a missing file", %{tmp_dir: tmp_dir} do
      assert {:error, :enoent} =
               DefinitionFileActions.delete_file(Path.join(tmp_dir, "missing.md"))
    end
  end
end
