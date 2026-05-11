defmodule EyeInTheSky.CredoChecks.RepoInEnumTest do
  use Credo.Test.Case, async: true

  alias EyeInTheSky.CredoChecks.RepoInEnum

  setup_all do
    {:ok, _} = Application.ensure_all_started(:credo)
    :ok
  end

  # NOTE on AST shape: the check uses `Credo.Code.Block.calls_in_do_block/1`
  # against the body of each `fn` clause. That helper extracts a `[do: ...]`
  # keyword from a node's arguments, so it only finds Repo calls when the
  # `fn` body itself wraps the Repo call in another do-block construct
  # (commonly `if cond, do: Repo.x()` or `case x do ... end`). The tests
  # below are crafted around that real behaviour.

  describe "flagged patterns — Enum function variants" do
    test "flags Repo call inside Enum.each via if-do" do
      """
      defmodule Sample do
        def run(items, cond?) do
          Enum.each(items, fn i ->
            if cond?, do: Repo.delete(i)
          end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Enum.each"
        assert issue.message =~ "N+1"
        assert issue.message =~ "Enum.each"
        assert is_integer(issue.line_no)
      end)
    end

    test "flags Repo call inside Enum.map via if-do" do
      """
      defmodule Sample do
        def run(items, c) do
          Enum.map(items, fn i -> if c, do: Repo.get(Foo, i) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> assert_issue(fn issue -> assert issue.trigger == "Enum.map" end)
    end

    test "flags Repo call inside Enum.flat_map via if-do" do
      """
      defmodule Sample do
        def run(items, c) do
          Enum.flat_map(items, fn i -> if c, do: Repo.all(i) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> assert_issue(fn issue -> assert issue.trigger == "Enum.flat_map" end)
    end

    test "flags Repo call inside Enum.reduce/2 via if-do" do
      """
      defmodule Sample do
        def run(items, c) do
          Enum.reduce(items, fn i, acc -> if c, do: Repo.insert(i), else: acc end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> assert_issue(fn issue -> assert issue.trigger == "Enum.reduce" end)
    end

    test "flags Repo call inside Enum.reduce_while/2 via if-do" do
      """
      defmodule Sample do
        def run(items, c) do
          Enum.reduce_while(items, fn i, acc -> if c, do: Repo.insert(i), else: acc end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> assert_issue(fn issue -> assert issue.trigger == "Enum.reduce_while" end)
    end
  end

  describe "flagged patterns — Repo alias variants" do
    test "flags single-segment custom alias ending in 'Repo' (e.g. MyRepo.x)" do
      """
      defmodule Sample do
        def run(items, c) do
          Enum.each(items, fn i -> if c, do: MyRepo.update_all(i, []) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> assert_issue(fn issue -> assert issue.trigger == "Enum.each" end)
    end

    test "reports the line number of the Enum call" do
      """
      defmodule Sample do
        def run(items, c) do
          Enum.map(items, fn i ->
            if c, do: Repo.get(Foo, i)
          end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> assert_issue(fn issue -> assert issue.line_no == 3 end)
    end

    test "flags multiple violations in the same source file" do
      """
      defmodule Sample do
        def a(items, c), do: Enum.each(items, fn i -> if c, do: Repo.delete(i) end)
        def b(items, c), do: Enum.map(items, fn i -> if c, do: Repo.get(Foo, i) end)
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> assert_issues(fn issues ->
        assert length(issues) == 2
        triggers = issues |> Enum.map(& &1.trigger) |> Enum.sort()
        assert triggers == ["Enum.each", "Enum.map"]
      end)
    end
  end

  describe "non-flagged patterns" do
    test "does not flag Enum.each without any Repo call" do
      """
      defmodule Sample do
        def run(items) do
          Enum.each(items, fn i -> IO.inspect(i) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> refute_issues()
    end

    test "does not flag Enum funs outside the watched set (e.g. Enum.filter)" do
      """
      defmodule Sample do
        def run(items, c) do
          Enum.filter(items, fn i -> if c, do: Repo.get(Foo, i) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> refute_issues()
    end

    test "does not flag a bare Repo call outside of any Enum block" do
      """
      defmodule Sample do
        def run(id) do
          Repo.get(Foo, id)
        end
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> refute_issues()
    end

    test "does not flag a capture-form block (no fn -> body)" do
      # Capture form `&Mod.fun/1` is not an :fn AST node, so the
      # `repo_call_in_block?(_)` fallthrough returns false.
      """
      defmodule Sample do
        def run(items) do
          Enum.each(items, &IO.inspect/1)
        end
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> refute_issues()
    end

    test "does not flag a multi-segment module alias ending in Repo (Foo.Bar.Repo.x)" do
      # Multi-segment aliases like `Foo.Bar.Repo.x()` are intentionally
      # not matched — only single-segment :Repo or `*Repo` aliases trigger.
      """
      defmodule Sample do
        def run(items, c) do
          Enum.each(items, fn i -> if c, do: Foo.Bar.Repo.delete(i) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> refute_issues()
    end

    test "does not flag a non-Repo call inside an Enum block" do
      """
      defmodule Sample do
        def run(items, c) do
          Enum.map(items, fn i -> if c, do: Other.do_something(i) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> refute_issues()
    end

    test "does not flag a non-aliased local function call" do
      # A bare `delete(i)` call (no alias) does not match any repo_call?
      # head and falls through to the catchall, so no issue is raised.
      """
      defmodule Sample do
        def run(items, c) do
          Enum.each(items, fn i -> if c, do: delete(i) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> refute_issues()
    end

    test "does not flag the piped form (LHS-as-collection)" do
      # In `items |> Enum.each(fn ...)`, the AST node for `Enum.each` has
      # only one explicit argument (the fn). The traverse pattern requires
      # `[_collection, block]` (two arguments), so the pipe form is not
      # matched by the current implementation.
      """
      defmodule Sample do
        def run(items, c) do
          items |> Enum.each(fn i -> if c, do: Repo.delete(i) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> refute_issues()
    end

    test "does not flag a single-segment alias that does not end in 'Repo'" do
      """
      defmodule Sample do
        def run(items, c) do
          Enum.each(items, fn i -> if c, do: Cache.put(i, :v) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RepoInEnum)
      |> refute_issues()
    end
  end

  describe "module metadata" do
    test "exposes the standard Credo check explanations and category" do
      Code.ensure_loaded!(RepoInEnum)
      assert function_exported?(RepoInEnum, :run, 2)
      assert RepoInEnum.category() == :warning
      assert RepoInEnum.base_priority() == :high
    end
  end
end
