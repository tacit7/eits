defmodule EyeInTheSky.CredoChecks.RepoInEnum do
  @moduledoc """
  Credo check: flags `Repo.*` calls inside `Enum.each`, `Enum.map`,
  `Enum.flat_map`, or `Enum.reduce` blocks.

  This pattern is the most common source of N+1 queries in this codebase.
  Each loop iteration issues a separate DB round-trip; replace with a single
  batch query (`Repo.insert_all`, `Repo.update_all`, `Repo.all` + Map.new, etc.)

  ## Examples

  Wrong:

      Enum.each(sessions, fn s ->
        Repo.update_all(from(t in Task, where: t.session_id == ^s.id), set: [...])
      end)

  Right:

      ids = Enum.map(sessions, & &1.id)
      Repo.update_all(from(t in Task, where: t.session_id in ^ids), set: [...])
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:n_plus_one, :performance],
    explanations: [
      check: @moduledoc,
      params: []
    ]

  alias Credo.Code.Block

  @enum_funs ~w(each map flat_map reduce reduce_while)a

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta))
  end

  # Match: Enum.each/map/flat_map/reduce(thing, fn ... end)
  # We look for a pipe into one of these OR a direct call.
  defp traverse(
         {{:., _, [{:__aliases__, _, [:Enum]}, fun]}, meta, [_collection, block]} = ast,
         issues,
         issue_meta
       )
       when fun in @enum_funs do
    if repo_call_in_block?(block) do
      {ast, [issue(issue_meta, meta[:line], fun) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _), do: {ast, issues}

  # Check whether the block argument (fn ... end or &...) contains a Repo call
  defp repo_call_in_block?({:fn, _, clauses}) do
    Enum.any?(clauses, fn {:->, _, [_args, body]} ->
      Block.calls_in_do_block(body)
      |> Enum.any?(&repo_call?/1)
    end)
  end

  defp repo_call_in_block?(_), do: false

  defp repo_call?({{:., _, [{:__aliases__, _, [:Repo]}, _fun]}, _, _}), do: true

  defp repo_call?({{:., _, [{:__aliases__, _, [repo]}, _fun]}, _, _}) do
    repo |> Atom.to_string() |> String.ends_with?("Repo")
  end

  defp repo_call?(_), do: false

  defp issue(issue_meta, line_no, enum_fun) do
    format_issue(issue_meta,
      message: "Repo call inside Enum.#{enum_fun} — likely N+1. Use a batch query instead.",
      trigger: "Enum.#{enum_fun}",
      line_no: line_no
    )
  end
end
