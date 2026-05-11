defmodule Mix.Tasks.Audit.EctoTest do
  # async: false — each test spawns a System.cmd mix subprocess.
  # Running these concurrently saturates CI runners and causes timeouts.
  use ExUnit.Case, async: false

  # Each test spawns a mix subprocess via System.cmd. Give CI runners
  # generous headroom — 5 minutes per test.
  @moduletag timeout: 300_000

  # Mix.Tasks.Audit.Ecto always calls System.halt/1 (both the clean and findings
  # paths). Running it in-process with CaptureIO would terminate the BEAM.
  # We spawn each invocation via System.cmd so the halt stays in a subprocess
  # and we capture {output, exit_code} safely.

  @project_root File.cwd!()

  setup do
    suffix = System.unique_integer([:positive])
    tmp = Path.join(System.tmp_dir!(), "audit_ecto_#{suffix}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  # Run mix audit.ecto --path <path> as a subprocess; returns {output, exit_code}.
  defp run_task(path) do
    System.cmd(
      "mix",
      ["audit.ecto", "--path", path],
      stderr_to_stdout: true,
      cd: @project_root
    )
  end

  # Write a fixture .ex file into the tmp directory.
  defp fixture(dir, name, content) do
    File.write!(Path.join(dir, name), content)
  end

  # ---------------------------------------------------------------------------
  # No findings — exit 0
  # ---------------------------------------------------------------------------

  describe "no findings" do
    test "empty directory exits 0 with 'No findings' message", %{tmp: tmp} do
      {output, exit_code} = run_task(tmp)

      assert exit_code == 0
      assert output =~ "No findings"
    end

    test "clean file with bounded query exits 0", %{tmp: tmp} do
      fixture(tmp, "clean.ex", """
      defmodule Clean do
        def users do
          User
          |> limit(50)
          |> Repo.all()
        end

        def stamp, do: DateTime.utc_now()
      end
      """)

      {output, exit_code} = run_task(tmp)

      assert exit_code == 0
      assert output =~ "No findings"
    end

    test "scan header includes the given path", %{tmp: tmp} do
      {output, _} = run_task(tmp)

      assert output =~ "mix audit.ecto scanning"
      assert output =~ tmp
    end
  end

  # ---------------------------------------------------------------------------
  # repo_in_enum — HIGH severity
  # ---------------------------------------------------------------------------

  describe "repo_in_enum" do
    test "flags Repo call inside Enum.map on the same line", %{tmp: tmp} do
      fixture(tmp, "n1_map.ex", """
      defmodule N1Map do
        def run(ids), do: Enum.map(ids, fn id -> Repo.get!(User, id) end)
      end
      """)

      {output, exit_code} = run_task(tmp)

      assert exit_code == 1
      assert output =~ "n1_map.ex"
      assert output =~ "HIGH"
      assert output =~ "N+1" or output =~ "repo_in_enum"
    end

    test "flags Repo call inside Enum.each", %{tmp: tmp} do
      fixture(tmp, "n1_each.ex", """
      defmodule N1Each do
        def run(users), do: Enum.each(users, fn u -> Repo.update!(u, %{seen: true}) end)
      end
      """)

      {_output, exit_code} = run_task(tmp)
      assert exit_code == 1
    end

    test "flags Repo call inside Enum.flat_map", %{tmp: tmp} do
      fixture(tmp, "n1_flat.ex", """
      defmodule N1Flat do
        def run(ts), do: Enum.flat_map(ts, fn t -> Repo.all(from m in M, where: m.t == ^t.id) end)
      end
      """)

      {_output, exit_code} = run_task(tmp)
      assert exit_code == 1
    end

    test "flags Repo call inside Enum.reduce", %{tmp: tmp} do
      fixture(tmp, "n1_reduce.ex", """
      defmodule N1Reduce do
        def run(ids), do: Enum.reduce(ids, [], fn id, acc -> [Repo.get!(User, id) | acc] end)
      end
      """)

      {_output, exit_code} = run_task(tmp)
      assert exit_code == 1
    end
  end

  # ---------------------------------------------------------------------------
  # unbounded_repo_all — HIGH severity
  # ---------------------------------------------------------------------------

  describe "unbounded_repo_all" do
    test "flags Repo.all without any limit call", %{tmp: tmp} do
      fixture(tmp, "unbounded.ex", """
      defmodule Unbounded do
        def all, do: Repo.all(User)
      end
      """)

      {output, exit_code} = run_task(tmp)

      assert exit_code == 1
      assert output =~ "unbounded" or output =~ "limit"
    end

    test "does not flag Repo.all when limit( is piped within 5 lines above", %{tmp: tmp} do
      fixture(tmp, "bounded.ex", """
      defmodule Bounded do
        def paged do
          User
          |> where([u], u.active == true)
          |> limit(50)
          |> Repo.all()
        end
      end
      """)

      {output, exit_code} = run_task(tmp)

      assert exit_code == 0
      assert output =~ "No findings"
    end

    test "does not flag Repo.all when limit( is on the same line", %{tmp: tmp} do
      fixture(tmp, "same_line.ex", """
      defmodule SameLine do
        def run, do: Repo.all(limit(User, 10))
      end
      """)

      {output, exit_code} = run_task(tmp)

      assert exit_code == 0
      assert output =~ "No findings"
    end

    test "flags Repo.all when limit is expressed as keyword (no parens — not detected by heuristic)",
         %{tmp: tmp} do
      # The check pattern looks for `limit(` (with parens). Ecto keyword syntax
      # `limit: 100` does NOT satisfy the absence check, so the line is flagged.
      # This is a documented heuristic limitation.
      fixture(tmp, "keyword_limit.ex", """
      defmodule KeywordLimit do
        def run, do: Repo.all(from u in User, limit: 100)
      end
      """)

      {_output, exit_code} = run_task(tmp)
      # flagged because `limit:` (no parens) doesn't match the absence pattern
      assert exit_code == 1
    end
  end

  # ---------------------------------------------------------------------------
  # naive_datetime — MEDIUM severity
  # ---------------------------------------------------------------------------

  describe "naive_datetime" do
    test "flags NaiveDateTime.utc_now usage", %{tmp: tmp} do
      fixture(tmp, "naive.ex", """
      defmodule Naive do
        def ts, do: NaiveDateTime.utc_now()
      end
      """)

      {output, exit_code} = run_task(tmp)

      assert exit_code == 1
      assert output =~ "naive.ex"
      assert output =~ "MEDIUM"
      assert output =~ "NaiveDateTime" or output =~ "naive_datetime"
    end
  end

  # ---------------------------------------------------------------------------
  # enum_uniq_by_post — MEDIUM severity
  # ---------------------------------------------------------------------------

  describe "enum_uniq_by_post" do
    test "flags Enum.uniq_by applied after a query", %{tmp: tmp} do
      fixture(tmp, "uniq.ex", """
      defmodule Uniq do
        def unique_users, do: Repo.all(User) |> Enum.uniq_by(& &1.email)
      end
      """)

      {output, exit_code} = run_task(tmp)

      assert exit_code == 1
      assert output =~ "uniq.ex"
      assert output =~ "uniq_by" or output =~ "DISTINCT"
    end
  end

  # ---------------------------------------------------------------------------
  # inline_preload — HIGH severity
  # ---------------------------------------------------------------------------

  describe "inline_preload" do
    test "flags Repo.preload inside Enum.map on the same line", %{tmp: tmp} do
      fixture(tmp, "preload_map.ex", """
      defmodule PreloadMap do
        def run(users), do: Enum.map(users, fn u -> Repo.preload(u, :posts) end)
      end
      """)

      {output, exit_code} = run_task(tmp)

      assert exit_code == 1
      assert output =~ "HIGH"
      assert output =~ "preload" or output =~ "N+1"
    end

    test "flags Repo.preload inside Enum.each on the same line", %{tmp: tmp} do
      fixture(tmp, "preload_each.ex", """
      defmodule PreloadEach do
        def run(users), do: Enum.each(users, fn u -> Repo.preload(u, :posts) end)
      end
      """)

      {_output, exit_code} = run_task(tmp)
      assert exit_code == 1
    end
  end

  # ---------------------------------------------------------------------------
  # load_then_find — MEDIUM severity
  # ---------------------------------------------------------------------------

  describe "load_then_find" do
    test "flags Enum.find on a query result", %{tmp: tmp} do
      fixture(tmp, "find.ex", """
      defmodule Find do
        def admin, do: Repo.all(User) |> Enum.find(fn u -> u.role == :admin end)
      end
      """)

      {output, exit_code} = run_task(tmp)

      assert exit_code == 1
      assert output =~ "find.ex"
      assert output =~ "Enum.find" or output =~ "load_then_find"
    end
  end

  # ---------------------------------------------------------------------------
  # coalesce_where — MEDIUM severity
  # The pattern requires `where`, `fragment`, and `COALESCE` on the same line.
  # ---------------------------------------------------------------------------

  describe "coalesce_where" do
    test "flags COALESCE inside a where fragment (uppercase, same line)", %{tmp: tmp} do
      fixture(tmp, "coalesce.ex", """
      defmodule Coalesce do
        def q(val), do: from u in User, where: fragment("COALESCE(?, 0) = ?", u.score, ^val)
      end
      """)

      {output, exit_code} = run_task(tmp)

      assert exit_code == 1
      assert output =~ "coalesce.ex"
      assert output =~ "COALESCE" or output =~ "coalesce_where"
    end

    test "flags coalesce in lowercase (case-insensitive match)", %{tmp: tmp} do
      fixture(tmp, "coalesce_lower.ex", """
      defmodule CoalesceLower do
        def q(val), do: from u in User, where: fragment("coalesce(?, 0) = ?", u.score, ^val)
      end
      """)

      {_output, exit_code} = run_task(tmp)
      assert exit_code == 1
    end
  end

  # ---------------------------------------------------------------------------
  # Output format — summary, severity labels, sorting
  # ---------------------------------------------------------------------------

  describe "output format" do
    test "summary line includes total finding count and severity buckets", %{tmp: tmp} do
      fixture(tmp, "multi.ex", """
      defmodule Multi do
        def a, do: NaiveDateTime.utc_now()
        def b, do: Repo.all(User)
      end
      """)

      {output, _} = run_task(tmp)

      assert output =~ "finding(s)"
      assert output =~ "HIGH"
      assert output =~ "MEDIUM"
    end

    test "output includes the matched source line text", %{tmp: tmp} do
      fixture(tmp, "source_line.ex", """
      defmodule SourceLine do
        def ts, do: NaiveDateTime.utc_now()
      end
      """)

      {output, _} = run_task(tmp)

      assert output =~ "NaiveDateTime.utc_now"
    end

    test "output includes file path and line number", %{tmp: tmp} do
      fixture(tmp, "located.ex", """
      defmodule Located do
        def ts, do: NaiveDateTime.utc_now()
      end
      """)

      {output, _} = run_task(tmp)

      # The finding line number format is "file.ex:N"
      assert output =~ ~r/located\.ex:\d+/
    end

    test "HIGH findings appear before MEDIUM findings in output", %{tmp: tmp} do
      fixture(tmp, "both.ex", """
      defmodule Both do
        def a, do: NaiveDateTime.utc_now()
        def b(ids), do: Enum.map(ids, fn id -> Repo.get!(User, id) end)
      end
      """)

      {output, _} = run_task(tmp)

      high_pos = :binary.match(output, "HIGH") |> elem(0)
      medium_pos = :binary.match(output, "MEDIUM") |> elem(0)

      # HIGH findings sorted first (lower severity_order value)
      assert high_pos < medium_pos
    end
  end

  # ---------------------------------------------------------------------------
  # Default path (no --path flag) — integration sanity check
  # ---------------------------------------------------------------------------

  describe "default path" do
    test "defaults to scanning lib/ when --path is omitted" do
      {output, _} =
        System.cmd("mix", ["audit.ecto"],
          stderr_to_stdout: true,
          cd: @project_root
        )

      assert output =~ "scanning lib/"
    end
  end

  # ---------------------------------------------------------------------------
  # Multiple anti-patterns in one file
  # ---------------------------------------------------------------------------

  describe "multiple anti-patterns" do
    @tag timeout: 120_000
    test "reports all distinct findings from a single file", %{tmp: tmp} do
      fixture(tmp, "everything.ex", """
      defmodule Everything do
        def a, do: NaiveDateTime.utc_now()
        def b, do: Repo.all(User)
        def c(ids), do: Enum.map(ids, fn id -> Repo.get!(User, id) end)
        def d(list), do: Repo.all(User) |> Enum.uniq_by(& &1.id)
      end
      """)

      {output, exit_code} = run_task(tmp)

      assert exit_code == 1
      # Should surface multiple finding lines — at least 3 distinct patterns
      finding_count =
        output
        |> String.split("\n")
        |> Enum.count(&(&1 =~ ~r/\[(?:HIGH|MEDIUM|LOW)\s*\]/))

      assert finding_count >= 3
    end
  end
end
