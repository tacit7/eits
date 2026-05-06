defmodule Mix.Tasks.Audit.Ecto do
  @shortdoc "Scan codebase for common Ecto anti-patterns"
  @moduledoc """
  Scans the lib/ tree for known Ecto anti-patterns that have caused production
  performance issues in this codebase. This is a pattern-match heuristic — not
  a type-checker — so review each hit before acting on it.

  ## Usage

      mix audit.ecto               # scan lib/
      mix audit.ecto --path lib/eye_in_the_sky/messages

  ## Checks

    - **repo_in_enum** — `Repo.*` call site inside `Enum.each/map/reduce/flat_map`
    - **unbounded_repo_all** — `Repo.all` without a `limit(` call in the same query chain
    - **naive_datetime** — `NaiveDateTime.utc_now` (schema uses :utc_datetime_usec)
    - **enum_uniq_by_post** — `Enum.uniq_by` applied to a list that came from `Repo.all`
    - **inline_preload** — `Repo.preload` called on a result inside a comprehension
    - **load_then_find** — `Repo.all` followed by `Enum.find` on the same binding
    - **coalesce_where** — `fragment("COALESCE")` inside a `where(` — prevents index use

  Exit codes:
    - 0  no findings
    - 1  one or more findings
  """

  use Mix.Task

  @checks [
    %{
      id: :repo_in_enum,
      severity: :high,
      description: "Repo call inside Enum.each/map/reduce/flat_map — likely N+1",
      # Match lines that have both an Enum higher-order function and a Repo call
      # (same line heuristic; multi-line cases require manual review)
      pattern: ~r/Enum\.(each|map|flat_map|reduce)\b.+Repo\./
    },
    %{
      id: :unbounded_repo_all,
      severity: :high,
      description: "Repo.all without a limit — unbounded result set",
      # A line with Repo.all( that does NOT have limit( anywhere on the same line
      pattern: ~r/Repo\.all\(/,
      # Exclusion: if limit( appears within 5 lines above, it's probably piped in
      requires_absence_of: ~r/limit\(/
    },
    %{
      id: :naive_datetime,
      severity: :medium,
      description:
        "NaiveDateTime.utc_now used — schema is :utc_datetime_usec, use DateTime.utc_now()",
      pattern: ~r/NaiveDateTime\.utc_now/
    },
    %{
      id: :enum_uniq_by_post,
      severity: :medium,
      description: "Enum.uniq_by after Repo.all — push dedup into DISTINCT ON query",
      pattern: ~r/Enum\.uniq_by/
    },
    %{
      id: :inline_preload,
      severity: :high,
      description: "Repo.preload inside Enum.map/each — N+1 preload",
      pattern: ~r/Enum\.(map|each)\b.+Repo\.preload/
    },
    %{
      id: :load_then_find,
      severity: :medium,
      description:
        "Enum.find on a Repo.all result — load all + filter in Elixir; use direct WHERE query",
      pattern: ~r/Enum\.find\(/
    },
    %{
      id: :coalesce_where,
      severity: :medium,
      description: "COALESCE in WHERE fragment — prevents index use on nullable column",
      pattern: ~r/where.+fragment.+COALESCE/i
    }
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [path: :string])
    scan_path = Keyword.get(opts, :path, "lib")

    Mix.shell().info([:cyan, "==> mix audit.ecto scanning #{scan_path}/", :reset])
    Mix.shell().info("")

    findings =
      scan_path
      |> find_elixir_files()
      |> Enum.flat_map(&check_file/1)
      |> Enum.sort_by(fn f -> {severity_order(f.severity), f.file} end)

    if findings == [] do
      Mix.shell().info([:green, "No findings. Clean.", :reset])
      System.halt(0)
    else
      print_findings(findings)
      summary(findings)
      System.halt(1)
    end
  end

  # ---------------------------------------------------------------------------

  defp find_elixir_files(path) do
    Path.wildcard("#{path}/**/*.ex")
  end

  defp check_file(path) do
    lines = File.read!(path) |> String.split("\n")
    Enum.flat_map(@checks, &run_check(&1, path, lines))
  end

  defp run_check(%{id: id, severity: sev, description: desc, pattern: pat} = check, path, lines) do
    absence = Map.get(check, :requires_absence_of)
    context_window = 5

    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> Regex.match?(pat, line) end)
    |> Enum.filter(fn {line, lineno} ->
      if absence do
        # Check window above for the absence pattern (e.g. limit piped above)
        start_idx = max(0, lineno - context_window - 1)
        window = Enum.slice(lines, start_idx, context_window + 1)

        not Enum.any?(window, &Regex.match?(absence, &1)) and
          not Regex.match?(absence, line)
      else
        _ = line
        true
      end
    end)
    |> Enum.map(fn {line, lineno} ->
      %{
        id: id,
        severity: sev,
        description: desc,
        file: path,
        line: lineno,
        text: String.trim(line)
      }
    end)
  end

  defp print_findings(findings) do
    Enum.each(findings, fn f ->
      color = severity_color(f.severity)
      tag = f.severity |> Atom.to_string() |> String.upcase() |> String.pad_trailing(6)

      Mix.shell().info([
        color,
        "[#{tag}] #{f.file}:#{f.line}",
        :reset,
        " — #{f.description}"
      ])

      Mix.shell().info([:faint, "       #{f.text}", :reset])
      Mix.shell().info("")
    end)
  end

  defp summary(findings) do
    by_sev = Enum.group_by(findings, & &1.severity)
    high = length(Map.get(by_sev, :high, []))
    medium = length(Map.get(by_sev, :medium, []))
    low = length(Map.get(by_sev, :low, []))
    total = length(findings)

    Mix.shell().info([
      :bright,
      "#{total} finding(s): ",
      :red,
      "#{high} HIGH  ",
      :yellow,
      "#{medium} MEDIUM  ",
      :cyan,
      "#{low} LOW",
      :reset
    ])
  end

  defp severity_order(:high), do: 0
  defp severity_order(:medium), do: 1
  defp severity_order(:low), do: 2
  defp severity_order(_), do: 3

  defp severity_color(:high), do: :red
  defp severity_color(:medium), do: :yellow
  defp severity_color(:low), do: :cyan
  defp severity_color(_), do: :normal
end
