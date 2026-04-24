defmodule EyeInTheSky.Projects.FileTreeTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias EyeInTheSky.Projects.FileTree

  @moduletag :tmp_dir

  describe "safe_path/2" do
    test "resolves safe relative path" do
      assert {:ok, path} = FileTree.safe_path("/tmp/project", "lib/foo.ex")
      assert path == "/tmp/project/lib/foo.ex"
    end

    test "resolves empty path to root" do
      assert {:ok, path} = FileTree.safe_path("/tmp/project", "")
      assert path == "/tmp/project"
    end

    test "rejects absolute path /etc/passwd before any trimming" do
      assert {:error, :absolute_path_not_allowed} = FileTree.safe_path("/tmp/project", "/etc/passwd")
    end

    test "rejects ../ traversal" do
      assert {:error, :outside_project} = FileTree.safe_path("/tmp/project", "../etc/passwd")
    end

    test "rejects path outside project" do
      assert {:error, :outside_project} = FileTree.safe_path("/tmp/project", "../../etc/passwd")
    end

    test "rejects sibling project path" do
      assert {:error, :outside_project} = FileTree.safe_path("/tmp/project", "../project2/file")
    end

    test "handles embedded ../ that stays inside project" do
      assert {:ok, path} = FileTree.safe_path("/tmp/project", "lib/../config/dev.exs")
      assert path == "/tmp/project/config/dev.exs"
    end
  end

  describe "root/2 and children/3" do
    setup %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "lib"))
      File.mkdir_p!(Path.join(tmp_dir, "config"))
      File.write!(Path.join(tmp_dir, "lib/foo.ex"), "defmodule Foo do\nend")
      File.write!(Path.join(tmp_dir, "lib/bar.ex"), "defmodule Bar do\nend")
      File.write!(Path.join(tmp_dir, "config/dev.exs"), "import Config")
      File.write!(Path.join(tmp_dir, ".env"), "SECRET=abc")
      File.write!(Path.join(tmp_dir, "README.md"), "# Readme")

      %{root: tmp_dir}
    end

    test "lists root directory entries", %{root: root} do
      assert {:ok, nodes} = FileTree.root(root)

      names = Enum.map(nodes, & &1.name)
      assert "lib" in names
      assert "config" in names
      assert ".env" in names
      assert "README.md" in names
    end

    test "directories sort before files", %{root: root} do
      assert {:ok, nodes} = FileTree.root(root)

      dirs = Enum.filter(nodes, &(&1.type == :directory))
      files = Enum.filter(nodes, &(&1.type == :file))

      dir_indices = Enum.map(dirs, fn d -> Enum.find_index(nodes, &(&1.name == d.name)) end)
      file_indices = Enum.map(files, fn f -> Enum.find_index(nodes, &(&1.name == f.name)) end)

      assert Enum.max(dir_indices) < Enum.min(file_indices)
    end

    test "lists children of subdirectory", %{root: root} do
      assert {:ok, nodes} = FileTree.children(root, "lib")

      names = Enum.map(nodes, & &1.name)
      assert "foo.ex" in names
      assert "bar.ex" in names
    end

    test "marks .env as sensitive", %{root: root} do
      assert {:ok, nodes} = FileTree.root(root)

      env_node = Enum.find(nodes, &(&1.name == ".env"))
      assert env_node.sensitive? == true
    end

    test "marks regular files as editable", %{root: root} do
      assert {:ok, nodes} = FileTree.root(root)

      readme_node = Enum.find(nodes, &(&1.name == "README.md"))
      assert readme_node.editable? == true
    end

    test "directories are not editable", %{root: root} do
      assert {:ok, nodes} = FileTree.root(root)

      lib_node = Enum.find(nodes, &(&1.name == "lib"))
      assert lib_node.editable? == false
    end

    test "ignores .git directory", %{root: root} do
      File.mkdir_p!(Path.join(root, ".git"))
      assert {:ok, nodes} = FileTree.root(root)

      names = Enum.map(nodes, & &1.name)
      refute ".git" in names
    end

    test "ignores node_modules directory", %{root: root} do
      File.mkdir_p!(Path.join(root, "node_modules"))
      assert {:ok, nodes} = FileTree.root(root)

      names = Enum.map(nodes, & &1.name)
      refute "node_modules" in names
    end

    test "ignores _build directory", %{root: root} do
      File.mkdir_p!(Path.join(root, "_build"))
      assert {:ok, nodes} = FileTree.root(root)

      names = Enum.map(nodes, & &1.name)
      refute "_build" in names
    end
  end

  describe "read_file/3" do
    setup %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "hello.ex"), "defmodule Hello do\nend")
      File.write!(Path.join(tmp_dir, ".env"), "SECRET=abc")

      %{root: tmp_dir}
    end

    test "reads text file successfully", %{root: root} do
      assert {:ok, result} = FileTree.read_file(root, "hello.ex")

      assert result.content == "defmodule Hello do\nend"
      assert result.language == :elixir
      assert result.editable? == true
      assert result.symlink? == false
      assert is_binary(result.hash)
    end

    test "returns hash for conflict detection", %{root: root} do
      assert {:ok, result} = FileTree.read_file(root, "hello.ex")
      assert String.length(result.hash) == 64
    end

    test "marks sensitive files", %{root: root} do
      assert {:ok, result} = FileTree.read_file(root, ".env")
      assert result.sensitive? == true
    end

    test "rejects empty file path", %{root: root} do
      assert {:error, :missing_file_path} = FileTree.read_file(root, "")
    end

    test "rejects directory path", %{root: root} do
      File.mkdir_p!(Path.join(root, "subdir"))
      assert {:error, :path_is_directory} = FileTree.read_file(root, "subdir")
    end

    test "rejects large files", %{root: root} do
      large_content = String.duplicate("x", 1_000_001)
      File.write!(Path.join(root, "large.txt"), large_content)

      assert {:error, :file_too_large} = FileTree.read_file(root, "large.txt")
    end

    test "rejects binary files", %{root: root} do
      binary_content = <<0, 1, 2, 3, 0, 5, 6>>
      File.write!(Path.join(root, "binary.bin"), binary_content)

      assert {:error, :binary_file} = FileTree.read_file(root, "binary.bin")
    end

    test "rejects invalid UTF-8", %{root: root} do
      invalid_utf8 = <<0xFF, 0xFE, 0x00, 0x01>>
      File.write!(Path.join(root, "invalid.txt"), invalid_utf8)

      assert {:error, _} = FileTree.read_file(root, "invalid.txt")
    end

    test "rejects absolute path", %{root: root} do
      assert {:error, :absolute_path_not_allowed} = FileTree.read_file(root, "/etc/passwd")
    end

    test "rejects path outside project", %{root: root} do
      assert {:error, :outside_project} = FileTree.read_file(root, "../etc/passwd")
    end
  end

  describe "write_file/4" do
    setup %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "existing.ex"), "original content")

      %{root: tmp_dir}
    end

    test "writes content successfully", %{root: root} do
      {:ok, read_result} = FileTree.read_file(root, "existing.ex")
      original_hash = read_result.hash

      assert {:ok, result} = FileTree.write_file(root, "existing.ex", "new content", original_hash: original_hash)
      assert is_binary(result.hash)
      assert result.hash != original_hash

      assert File.read!(Path.join(root, "existing.ex")) == "new content"
    end

    test "rejects missing original_hash", %{root: root} do
      assert {:error, :missing_original_hash} = FileTree.write_file(root, "existing.ex", "new content")
    end

    test "rejects stale original hash (conflict)", %{root: root} do
      stale_hash = "0000000000000000000000000000000000000000000000000000000000000000"

      assert {:error, :conflict} = FileTree.write_file(root, "existing.ex", "new content", original_hash: stale_hash)
    end

    test "succeeds with force?: true", %{root: root} do
      assert {:ok, _result} = FileTree.write_file(root, "existing.ex", "forced content", force?: true)

      assert File.read!(Path.join(root, "existing.ex")) == "forced content"
    end

    test "rejects outside project path", %{root: root} do
      assert {:error, :outside_project} = FileTree.write_file(root, "../outside.txt", "content", force?: true)
    end

    test "rejects empty file path", %{root: root} do
      assert {:error, :missing_file_path} = FileTree.write_file(root, "", "content", force?: true)
    end

    test "preserves file permissions", %{root: root} do
      File.chmod!(Path.join(root, "existing.ex"), 0o755)

      {:ok, read_result} = FileTree.read_file(root, "existing.ex")
      {:ok, _} = FileTree.write_file(root, "existing.ex", "updated", original_hash: read_result.hash)

      {:ok, stat} = File.stat(Path.join(root, "existing.ex"))
      assert stat.mode == 0o100755
    end

    test "preserves executable bit", %{root: root} do
      script_path = Path.join(root, "script.sh")
      File.write!(script_path, "#!/bin/bash\necho hi")
      File.chmod!(script_path, 0o755)

      {:ok, read_result} = FileTree.read_file(root, "script.sh")
      {:ok, _} = FileTree.write_file(root, "script.sh", "#!/bin/bash\necho hello", original_hash: read_result.hash)

      {:ok, stat} = File.stat(script_path)
      assert (stat.mode &&& 0o111) != 0
    end

    test "validates UTF-8 content", %{root: root} do
      invalid_utf8 = <<0xFF, 0xFE>>

      assert {:error, :invalid_utf8} = FileTree.write_file(root, "existing.ex", invalid_utf8, force?: true)
    end

    test "returns file_deleted when file was deleted", %{root: root} do
      File.rm!(Path.join(root, "existing.ex"))

      assert {:error, :file_deleted} = FileTree.write_file(root, "existing.ex", "new content", force?: true)
    end

    test "cleans up temp file on failure", %{root: root} do
      File.chmod!(Path.join(root, "existing.ex"), 0o000)

      _result = FileTree.write_file(root, "existing.ex", "content", force?: true)

      File.chmod!(Path.join(root, "existing.ex"), 0o644)

      temp_files =
        File.ls!(root)
        |> Enum.filter(&String.match?(&1, ~r/^\.existing\.ex\.tmp-/))

      assert temp_files == []
    end
  end

  describe "symlinks" do
    setup %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "real_file.ex"), "real content")
      File.mkdir_p!(Path.join(tmp_dir, "subdir"))
      File.write!(Path.join(tmp_dir, "subdir/nested.ex"), "nested content")

      %{root: tmp_dir}
    end

    test "symlink to file inside project resolves", %{root: root} do
      link_path = Path.join(root, "linked_file.ex")
      File.ln_s!("real_file.ex", link_path)

      assert {:ok, result} = FileTree.read_file(root, "linked_file.ex")
      assert result.content == "real content"
      assert result.symlink? == true
      assert result.editable? == false
    end

    test "symlink to file outside project is rejected", %{root: root} do
      link_path = Path.join(root, "outside_link.ex")
      File.ln_s!("/etc/passwd", link_path)

      assert {:error, :symlink_escapes_project} = FileTree.read_file(root, "outside_link.ex")
    end

    test "symlinked files are not saveable", %{root: root} do
      link_path = Path.join(root, "linked_file.ex")
      File.ln_s!("real_file.ex", link_path)

      assert {:error, :symlink_not_saveable} = FileTree.write_file(root, "linked_file.ex", "new content", force?: true)
    end

    test "symlinked directory shows in listing but not expandable", %{root: root} do
      link_path = Path.join(root, "linked_dir")
      File.ln_s!("subdir", link_path)

      assert {:ok, nodes} = FileTree.root(root)

      linked_dir_node = Enum.find(nodes, &(&1.name == "linked_dir"))
      assert linked_dir_node.type == :directory
      assert linked_dir_node.symlink? == true
      assert linked_dir_node.expandable? == false
    end
  end

  describe "symlinked ancestor directory escape prevention" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      # Create an "outside" directory that should not be accessible
      outside_dir = Path.join(tmp_dir, "outside")
      File.mkdir_p!(outside_dir)
      File.write!(Path.join(outside_dir, "secret.txt"), "secret data")
      File.write!(Path.join(outside_dir, "passwd"), "root:x:0:0")

      # Create project directory
      project_dir = Path.join(tmp_dir, "project")
      File.mkdir_p!(project_dir)
      File.write!(Path.join(project_dir, "legit.ex"), "legit content")

      # Create symlinked directory inside project pointing outside
      linked_dir = Path.join(project_dir, "linked_dir")
      File.ln_s!(outside_dir, linked_dir)

      %{root: project_dir, outside_dir: outside_dir}
    end

    test "read_file rejects access through symlinked ancestor directory", %{root: root} do
      # Try to read /project/linked_dir/secret.txt which resolves to /outside/secret.txt
      assert {:error, :symlink_escapes_project} = FileTree.read_file(root, "linked_dir/secret.txt")
    end

    test "read_file rejects passwd through symlinked directory", %{root: root} do
      assert {:error, :symlink_escapes_project} = FileTree.read_file(root, "linked_dir/passwd")
    end

    test "write_file rejects write through symlinked ancestor directory", %{root: root, outside_dir: outside_dir} do
      # Try to write through the symlinked directory
      assert {:error, :symlink_escapes_project} =
               FileTree.write_file(root, "linked_dir/secret.txt", "pwned", force?: true)

      # Verify the original file was NOT modified
      assert File.read!(Path.join(outside_dir, "secret.txt")) == "secret data"
    end

    test "write_file rejects new file creation through symlinked ancestor", %{root: root, outside_dir: outside_dir} do
      # Try to create a new file through the symlinked directory
      assert {:error, :symlink_escapes_project} =
               FileTree.write_file(root, "linked_dir/newfile.txt", "malicious", force?: true)

      # Verify file was NOT created
      refute File.exists?(Path.join(outside_dir, "newfile.txt"))
    end

    test "children rejects listing through symlinked ancestor directory", %{root: root} do
      # Even though UI marks symlinked dirs as non-expandable, the API should also block
      assert {:error, :symlink_escapes_project} = FileTree.children(root, "linked_dir")
    end

    test "nested symlinked directory escape is blocked", %{root: root, outside_dir: outside_dir} do
      # Create nested structure: project/subdir/deep_link -> outside
      subdir = Path.join(root, "subdir")
      File.mkdir_p!(subdir)
      File.ln_s!(outside_dir, Path.join(subdir, "deep_link"))

      assert {:error, :symlink_escapes_project} = FileTree.read_file(root, "subdir/deep_link/secret.txt")
    end
  end

  describe "root_path validation" do
    test "rejects nil root_path" do
      assert {:error, :missing_root_path} = FileTree.children(nil, "")
    end

    test "rejects empty root_path" do
      assert {:error, :missing_root_path} = FileTree.children("", "")
    end

    test "rejects non-existent root_path" do
      assert {:error, :root_path_not_found} = FileTree.children("/nonexistent/path", "")
    end

    test "rejects file as root_path", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "file.txt")
      File.write!(file_path, "content")

      assert {:error, :root_path_not_directory} = FileTree.children(file_path, "")
    end
  end

  describe "sensitive?/1" do
    test ".env is sensitive" do
      assert FileTree.sensitive?(".env") == true
    end

    test ".env.local is sensitive" do
      assert FileTree.sensitive?(".env.local") == true
    end

    test ".env.production is sensitive" do
      assert FileTree.sensitive?(".env.production") == true
    end

    test "*.pem is sensitive" do
      assert FileTree.sensitive?("server.pem") == true
      assert FileTree.sensitive?("certs/ca.pem") == true
    end

    test "*.key is sensitive" do
      assert FileTree.sensitive?("private.key") == true
    end

    test "credentials.json is sensitive" do
      assert FileTree.sensitive?("credentials.json") == true
    end

    test "config/prod.secret.exs is sensitive" do
      assert FileTree.sensitive?("config/prod.secret.exs") == true
    end

    test "regular files are not sensitive" do
      assert FileTree.sensitive?("lib/foo.ex") == false
      assert FileTree.sensitive?("README.md") == false
    end
  end

  describe "language detection" do
    test "detects Elixir" do
      assert {:ok, result} = create_and_read_file("foo.ex", "code")
      assert result.language == :elixir
    end

    test "detects JavaScript" do
      assert {:ok, result} = create_and_read_file("app.js", "code")
      assert result.language == :javascript
    end

    test "detects TypeScript" do
      assert {:ok, result} = create_and_read_file("app.ts", "code")
      assert result.language == :typescript
    end

    test "detects Markdown" do
      assert {:ok, result} = create_and_read_file("README.md", "# Hi")
      assert result.language == :markdown
    end

    test "defaults to plaintext" do
      assert {:ok, result} = create_and_read_file("unknown.xyz", "content")
      assert result.language == :plaintext
    end

    defp create_and_read_file(filename, content) do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "lang_test_#{:erlang.unique_integer([:positive])}")
      File.mkdir_p!(test_dir)
      File.write!(Path.join(test_dir, filename), content)

      result = FileTree.read_file(test_dir, filename)

      File.rm_rf!(test_dir)
      result
    end
  end
end
