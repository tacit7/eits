defmodule EyeInTheSkyWeb.DmLive.FileAutocompleteTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.DmLive.FileAutocomplete

  defp session(path \\ nil), do: %{git_worktree_path: path}

  describe "list_entries/3 — root validation" do
    test "unknown root returns empty" do
      result = FileAutocomplete.list_entries("", "unknown", session())
      assert result == %{entries: [], truncated: false}
    end

    test "project root with nil worktree falls back to File.cwd!" do
      result = FileAutocomplete.list_entries("", "project", session(nil))
      assert is_list(result.entries)
      assert is_boolean(result.truncated)
    end

    test "home root resolves to user home dir entries" do
      result = FileAutocomplete.list_entries("", "home", session())
      assert is_list(result.entries)
    end

    test "filesystem root resolves to / entries" do
      result = FileAutocomplete.list_entries("", "filesystem", session())
      assert result.entries != []
    end
  end

  describe "list_entries/3 — traversal guard" do
    test "../ does not escape project root" do
      root = System.tmp_dir!()
      result = FileAutocomplete.list_entries("../../etc", "project", session(root))
      assert result == %{entries: [], truncated: false}
    end

    test "under_root? does not match prefix-extended paths" do
      refute FileAutocomplete.under_root?(
               "/Users/uriel/project-old",
               "/Users/uriel/project"
             )
    end

    test "under_root? accepts children of the root" do
      assert FileAutocomplete.under_root?(
               "/Users/uriel/project/src/foo.ex",
               "/Users/uriel/project"
             )
    end

    test "under_root? accepts path equal to root" do
      assert FileAutocomplete.under_root?(
               "/Users/uriel/project",
               "/Users/uriel/project"
             )
    end

    test "filesystem root / accepts all absolute paths" do
      assert FileAutocomplete.under_root?("/etc/hosts", "/")
      assert FileAutocomplete.under_root?("/usr/bin/env", "/")
    end
  end

  describe "list_entries/3 — sorting and filtering" do
    setup do
      root = Path.join(System.tmp_dir!(), "fa_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(root)
      File.mkdir_p!(Path.join(root, "alpha_dir"))
      File.mkdir_p!(Path.join(root, "beta_dir"))
      File.write!(Path.join(root, "alpha_file.txt"), "")
      File.write!(Path.join(root, "beta_file.txt"), "")
      on_exit(fn -> File.rm_rf!(root) end)
      {:ok, root: root}
    end

    test "directories appear before files", %{root: root} do
      result = FileAutocomplete.list_entries("", "project", session(root))
      dirs = Enum.take_while(result.entries, & &1.is_dir)
      assert length(dirs) == 2
      files = Enum.drop_while(result.entries, & &1.is_dir)
      assert Enum.all?(files, &(not &1.is_dir))
    end

    test "entries are alphabetized within each group", %{root: root} do
      result = FileAutocomplete.list_entries("", "project", session(root))
      dir_names = result.entries |> Enum.filter(& &1.is_dir) |> Enum.map(& &1.name)
      assert dir_names == Enum.sort(dir_names)
      file_names = result.entries |> Enum.reject(& &1.is_dir) |> Enum.map(& &1.name)
      assert file_names == Enum.sort(file_names)
    end

    test "prefix filter is case-sensitive and prefix-only", %{root: root} do
      result = FileAutocomplete.list_entries("alpha", "project", session(root))
      assert length(result.entries) == 2
      assert Enum.all?(result.entries, &String.starts_with?(&1.name, "alpha"))
    end

    test "dotfiles are shown by default", %{root: root} do
      File.write!(Path.join(root, ".env"), "")
      result = FileAutocomplete.list_entries("", "project", session(root))
      assert Enum.any?(result.entries, &(&1.name == ".env"))
    end
  end

  describe "list_entries/3 — excluded directories" do
    setup do
      root = Path.join(System.tmp_dir!(), "fa_excl_#{System.unique_integer([:positive])}")
      File.mkdir_p!(root)
      for dir <- ~w(.git node_modules deps _build .elixir_ls .tmp) do
        File.mkdir_p!(Path.join(root, dir))
      end
      File.mkdir_p!(Path.join(root, "lib"))
      on_exit(fn -> File.rm_rf!(root) end)
      {:ok, root: root}
    end

    test "noisy root-level dirs are hidden", %{root: root} do
      result = FileAutocomplete.list_entries("", "project", session(root))
      names = Enum.map(result.entries, & &1.name)
      assert "lib" in names
      for excluded <- ~w(.git node_modules deps _build .elixir_ls .tmp) do
        refute excluded in names, "Expected #{excluded} to be excluded"
      end
    end

    test "explicitly navigating into excluded dir returns its contents", %{root: root} do
      File.write!(Path.join([root, "node_modules", "foo.js"]), "")
      result = FileAutocomplete.list_entries("node_modules/", "project", session(root))
      assert Enum.any?(result.entries, &(&1.name == "foo.js"))
    end
  end

  describe "list_entries/3 — truncation" do
    setup do
      root = Path.join(System.tmp_dir!(), "fa_trunc_#{System.unique_integer([:positive])}")
      File.mkdir_p!(root)
      for i <- 1..55 do
        File.write!(Path.join(root, "file_#{String.pad_leading("#{i}", 3, "0")}.txt"), "")
      end
      on_exit(fn -> File.rm_rf!(root) end)
      {:ok, root: root}
    end

    test "returns at most 50 entries with truncated: true", %{root: root} do
      result = FileAutocomplete.list_entries("", "project", session(root))
      assert length(result.entries) == 50
      assert result.truncated == true
    end
  end

  describe "list_entries/3 — insert_text generation" do
    setup do
      root = Path.join(System.tmp_dir!(), "fa_ins_#{System.unique_integer([:positive])}")
      File.mkdir_p!(root)
      File.mkdir_p!(Path.join(root, "src"))
      File.write!(Path.join(root, "router.ex"), "")
      on_exit(fn -> File.rm_rf!(root) end)
      {:ok, root: root}
    end

    test "project root: insert_text starts with @", %{root: root} do
      result = FileAutocomplete.list_entries("", "project", session(root))
      router = Enum.find(result.entries, &(&1.name == "router.ex"))
      assert router.insert_text == "@router.ex"
      assert router.path == "router.ex"
    end

    test "project root directory: trailing slash in path and insert_text", %{root: root} do
      result = FileAutocomplete.list_entries("", "project", session(root))
      src = Enum.find(result.entries, &(&1.name == "src"))
      assert src.path == "src/"
      assert src.insert_text == "@src/"
    end

    test "home root: insert_text starts with @~/", %{root: _root} do
      result = FileAutocomplete.list_entries("", "home", session())
      assert result.entries != [], "expected home dir to have entries"
      assert String.starts_with?(hd(result.entries).insert_text, "@~/")
    end

    test "filesystem root: insert_text starts with @/", %{root: _root} do
      result = FileAutocomplete.list_entries("", "filesystem", session())
      assert result.entries != [], "expected filesystem root to have entries"
      entry = hd(result.entries)
      assert String.starts_with?(entry.insert_text, "@/")
      assert is_boolean(entry.is_dir)
    end
  end
end
