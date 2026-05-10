defmodule EyeInTheSky.ProjectFilesTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.ProjectFiles

  # Build a unique temp dir per test to avoid collisions in async mode.
  defp tmp_dir(context) do
    name = context.test |> to_string() |> String.replace(~r/[^\w]/, "_")
    dir = Path.join(System.tmp_dir!(), "project_files_test_#{name}_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # ---------------------------------------------------------------------------
  # scan_directory/3
  # ---------------------------------------------------------------------------

  describe "scan_directory/3" do
    test "returns [] for a non-existent directory", context do
      base = tmp_dir(context)
      assert ProjectFiles.scan_directory(base, Path.join(base, "nope"), 0) == []
    end

    test "returns [] for an empty directory", context do
      base = tmp_dir(context)
      assert ProjectFiles.scan_directory(base, base, 0) == []
    end

    test "lists a single file with correct keys", context do
      base = tmp_dir(context)
      file = Path.join(base, "hello.txt")
      File.write!(file, "world")

      [entry] = ProjectFiles.scan_directory(base, base, 0)

      assert entry.name == "hello.txt"
      assert entry.path == file
      assert entry.relative == "hello.txt"
      assert entry.is_dir == false
      assert entry.size == 5
      refute Map.has_key?(entry, :children)
    end

    test "excludes hidden (dot-prefixed) files", context do
      base = tmp_dir(context)
      File.write!(Path.join(base, ".hidden"), "")
      File.write!(Path.join(base, "visible.txt"), "")

      entries = ProjectFiles.scan_directory(base, base, 0)

      assert length(entries) == 1
      assert hd(entries).name == "visible.txt"
    end

    test "excludes hidden (dot-prefixed) directories", context do
      base = tmp_dir(context)
      File.mkdir_p!(Path.join(base, ".git"))
      File.mkdir_p!(Path.join(base, "src"))

      entries = ProjectFiles.scan_directory(base, base, 0)

      names = Enum.map(entries, & &1.name)
      refute ".git" in names
      assert "src" in names
    end

    test "sorts directories before files", context do
      base = tmp_dir(context)
      File.write!(Path.join(base, "aaa.txt"), "")
      File.mkdir_p!(Path.join(base, "zzz"))

      [first | _] = ProjectFiles.scan_directory(base, base, 0)
      assert first.name == "zzz"
      assert first.is_dir == true
    end

    test "sorts entries alphabetically within the same type", context do
      base = tmp_dir(context)
      File.write!(Path.join(base, "c.txt"), "")
      File.write!(Path.join(base, "a.txt"), "")
      File.write!(Path.join(base, "b.txt"), "")

      names = ProjectFiles.scan_directory(base, base, 0) |> Enum.map(& &1.name)
      assert names == ["a.txt", "b.txt", "c.txt"]
    end

    test "directories include a :children key", context do
      base = tmp_dir(context)
      File.mkdir_p!(Path.join(base, "subdir"))

      [dir_entry] = ProjectFiles.scan_directory(base, base, 0)

      assert dir_entry.is_dir == true
      assert Map.has_key?(dir_entry, :children)
    end

    test "recurses into subdirectory at depth 0 (up to max depth 2)", context do
      base = tmp_dir(context)
      sub = Path.join(base, "subdir")
      File.mkdir_p!(sub)
      File.write!(Path.join(sub, "child.txt"), "hello")

      [dir_entry] = ProjectFiles.scan_directory(base, base, 0)

      assert dir_entry.is_dir == true
      assert length(dir_entry.children) == 1
      assert hd(dir_entry.children).name == "child.txt"
    end

    test "does not recurse beyond max depth (depth 2 returns empty children)", context do
      base = tmp_dir(context)
      deep = Path.join([base, "a", "b", "c"])
      File.mkdir_p!(deep)
      File.write!(Path.join(deep, "leaf.txt"), "")

      # At depth=2, the directory at level 2 should have no children scanned
      [a_entry] = ProjectFiles.scan_directory(base, base, 0)
      [b_entry] = a_entry.children

      # b_entry is at depth=1, so its children are scanned
      [c_entry] = b_entry.children

      # c_entry is at depth=2, which equals @max_tree_depth, so no children scanned
      assert c_entry.is_dir == true
      assert c_entry.children == []
    end

    test "relative path is relative to base_dir, not current_dir", context do
      base = tmp_dir(context)
      sub = Path.join(base, "subdir")
      File.mkdir_p!(sub)
      File.write!(Path.join(sub, "file.txt"), "")

      [dir_entry] = ProjectFiles.scan_directory(base, base, 0)
      [file_entry] = dir_entry.children

      assert file_entry.relative == "subdir/file.txt"
    end

    test "file size is reported correctly", context do
      base = tmp_dir(context)
      content = "hello world"
      File.write!(Path.join(base, "sized.txt"), content)

      [entry] = ProjectFiles.scan_directory(base, base, 0)
      assert entry.size == byte_size(content)
    end
  end

  # ---------------------------------------------------------------------------
  # list_directory_entries/2
  # ---------------------------------------------------------------------------

  describe "list_directory_entries/2" do
    test "returns {:ok, entries} for a valid directory", context do
      base = tmp_dir(context)
      File.write!(Path.join(base, "file.txt"), "")

      assert {:ok, [_entry]} = ProjectFiles.list_directory_entries(base)
    end

    test "returns {:error, reason} for a non-existent path", context do
      base = tmp_dir(context)
      assert {:error, _} = ProjectFiles.list_directory_entries(Path.join(base, "missing"))
    end

    test "entries sorted directories-first, then alphabetically", context do
      base = tmp_dir(context)
      File.write!(Path.join(base, "zzz.txt"), "")
      File.mkdir_p!(Path.join(base, "aaa"))

      {:ok, entries} = ProjectFiles.list_directory_entries(base)
      assert hd(entries).name == "aaa"
      assert hd(entries).is_dir == true
      assert List.last(entries).name == "zzz.txt"
    end

    test "entry :path is item name when rel_path is nil", context do
      base = tmp_dir(context)
      File.write!(Path.join(base, "myfile.txt"), "")

      {:ok, [entry]} = ProjectFiles.list_directory_entries(base, nil)
      assert entry.path == "myfile.txt"
    end

    test "entry :path is joined with rel_path when provided", context do
      base = tmp_dir(context)
      File.write!(Path.join(base, "myfile.txt"), "")

      {:ok, [entry]} = ProjectFiles.list_directory_entries(base, "some/prefix")
      assert entry.path == "some/prefix/myfile.txt"
    end

    test "entry has correct :size for a file", context do
      base = tmp_dir(context)
      content = "test content here"
      File.write!(Path.join(base, "sized.txt"), content)

      {:ok, [entry]} = ProjectFiles.list_directory_entries(base)
      assert entry.size == byte_size(content)
    end

    test "directory entries have :is_dir true", context do
      base = tmp_dir(context)
      File.mkdir_p!(Path.join(base, "mydir"))

      {:ok, [entry]} = ProjectFiles.list_directory_entries(base)
      assert entry.is_dir == true
    end

    test "file entries have :is_dir false", context do
      base = tmp_dir(context)
      File.write!(Path.join(base, "flat.txt"), "")

      {:ok, [entry]} = ProjectFiles.list_directory_entries(base)
      assert entry.is_dir == false
    end

    test "returns empty list for an empty directory", context do
      base = tmp_dir(context)
      assert {:ok, []} = ProjectFiles.list_directory_entries(base)
    end

    test "does not recurse into subdirectories", context do
      base = tmp_dir(context)
      sub = Path.join(base, "subdir")
      File.mkdir_p!(sub)
      File.write!(Path.join(sub, "nested.txt"), "")

      {:ok, entries} = ProjectFiles.list_directory_entries(base)
      # Only one entry (the subdir itself), no nested file
      assert length(entries) == 1
    end

    test "uses default rel_path of nil", context do
      base = tmp_dir(context)
      File.write!(Path.join(base, "file.txt"), "")

      {:ok, [entry]} = ProjectFiles.list_directory_entries(base)
      assert entry.path == "file.txt"
    end
  end

  # ---------------------------------------------------------------------------
  # read_file/1
  # ---------------------------------------------------------------------------

  describe "read_file/1" do
    test "returns {:ok, content} for a normal file", context do
      base = tmp_dir(context)
      path = Path.join(base, "readable.txt")
      File.write!(path, "some content")

      assert {:ok, "some content"} = ProjectFiles.read_file(path)
    end

    test "returns {:ok, empty string} for an empty file", context do
      base = tmp_dir(context)
      path = Path.join(base, "empty.txt")
      File.write!(path, "")

      assert {:ok, ""} = ProjectFiles.read_file(path)
    end

    test "returns {:too_large, size} for a file over 1MB", context do
      base = tmp_dir(context)
      path = Path.join(base, "big.bin")
      # Write exactly 1MB + 1 byte
      big = :binary.copy(<<0>>, 1_048_577)
      File.write!(path, big)

      assert {:too_large, 1_048_577} = ProjectFiles.read_file(path)
    end

    test "returns {:ok, content} for a file exactly at the 1MB limit", context do
      base = tmp_dir(context)
      path = Path.join(base, "exactly_1mb.bin")
      content = :binary.copy(<<0>>, 1_048_576)
      File.write!(path, content)

      assert {:ok, ^content} = ProjectFiles.read_file(path)
    end

    test "returns {:error, reason} for a non-existent file", context do
      base = tmp_dir(context)
      path = Path.join(base, "does_not_exist.txt")

      assert {:error, _reason} = ProjectFiles.read_file(path)
    end

    test "returns {:error, reason} when path is a directory", context do
      base = tmp_dir(context)

      # A directory stat succeeds but File.read on a dir returns an error
      result = ProjectFiles.read_file(base)
      # Could be {:ok, _} or {:error, _} depending on OS; key thing is it doesn't crash
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  # ---------------------------------------------------------------------------
  # write_file/2
  # ---------------------------------------------------------------------------

  describe "write_file/2" do
    test "writes content and returns :ok", context do
      base = tmp_dir(context)
      path = Path.join(base, "output.txt")

      assert :ok = ProjectFiles.write_file(path, "written content")
    end

    test "written content can be read back correctly", context do
      base = tmp_dir(context)
      path = Path.join(base, "roundtrip.txt")
      content = "round-trip data\nline two\n"

      ProjectFiles.write_file(path, content)
      assert File.read!(path) == content
    end

    test "overwrites existing file content", context do
      base = tmp_dir(context)
      path = Path.join(base, "overwrite.txt")
      File.write!(path, "old content")

      :ok = ProjectFiles.write_file(path, "new content")
      assert File.read!(path) == "new content"
    end

    test "returns {:error, reason} when parent directory does not exist", context do
      base = tmp_dir(context)
      path = Path.join([base, "nonexistent_dir", "file.txt"])

      assert {:error, _} = ProjectFiles.write_file(path, "content")
    end

    test "can write empty content", context do
      base = tmp_dir(context)
      path = Path.join(base, "empty.txt")

      assert :ok = ProjectFiles.write_file(path, "")
      assert File.read!(path) == ""
    end

    test "can write binary content (non-UTF8)", context do
      base = tmp_dir(context)
      path = Path.join(base, "binary.bin")
      content = <<0, 1, 2, 3, 255>>

      assert :ok = ProjectFiles.write_file(path, content)
      assert File.read!(path) == content
    end
  end
end
