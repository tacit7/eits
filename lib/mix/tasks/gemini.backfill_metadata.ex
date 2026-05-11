defmodule Mix.Tasks.Gemini.BackfillMetadata do
  @moduledoc """
  Backfill metadata (token usage + duration_ms) for Gemini agent messages
  that were persisted before the atom-key fix in `stats_to_map/1`.

  Pre-fix Gemini messages were saved with `metadata = NULL` because the
  StreamHandler emitted a string-keyed map but `build_db_metadata/1`
  pluck-by-atom returned all nils. The on-disk session JSONL still has
  the per-turn `tokens` and `timestamp` data, so we can reconstruct
  what should have been persisted.

  Walks every Gemini session, locates its session file under
  `~/.gemini/tmp/<proj>/chats/`, then for each agent row whose
  `metadata IS NULL` (or whose `metadata.usage` is missing), finds the
  matching turn in the JSONL by `source_uuid` (we store the Gemini turn
  id there) and rewrites the row's metadata.

  Duration is approximated as `current_turn.timestamp − previous_turn.timestamp`
  in milliseconds, which is what the live worker recorded as `duration_ms`
  for completed turns.

  ## Usage

      mix gemini.backfill_metadata               # All Gemini sessions
      mix gemini.backfill_metadata --session 4957 # One session by id
      mix gemini.backfill_metadata --dry-run     # Report what would change
  """

  use Mix.Task

  alias EyeInTheSky.Gemini.SessionReader
  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Sessions.Session

  import Ecto.Query

  @shortdoc "Backfill token + duration metadata on legacy Gemini agent rows"

  @impl Mix.Task
  def run(args) do
    # Don't go through app.start — that boots the web endpoint and collides
    # with a running dev server on port 5001. We only need Repo for this
    # backfill, so load config + start ecto + the Repo directly.
    Mix.Task.run("app.config")
    Application.ensure_all_started(:postgrex)
    Application.ensure_all_started(:ecto_sql)
    {:ok, _} = EyeInTheSky.Repo.start_link()

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [session: :integer, dry_run: :boolean],
        aliases: [s: :session, d: :dry_run]
      )

    dry_run? = Keyword.get(opts, :dry_run, false)
    only_session = Keyword.get(opts, :session)

    sessions = list_gemini_sessions(only_session)
    Mix.shell().info("Found #{length(sessions)} Gemini session(s) to inspect")

    totals =
      Enum.reduce(sessions, %{scanned: 0, matched: 0, updated: 0, missing_file: 0}, fn s, acc ->
        process_session(s, dry_run?, acc)
      end)

    Mix.shell().info("""

    Backfill summary:
      scanned rows ..... #{totals.scanned}
      matched turns .... #{totals.matched}
      updated rows ..... #{totals.updated}#{if dry_run?, do: " (dry run — no writes)", else: ""}
      sessions w/o file. #{totals.missing_file}
    """)
  end

  defp list_gemini_sessions(nil) do
    Repo.all(from s in Session, where: s.provider == "gemini", select: s)
  end

  defp list_gemini_sessions(session_id) do
    case Repo.get(Session, session_id) do
      nil -> []
      %Session{provider: "gemini"} = s -> [s]
      _ -> []
    end
  end

  defp process_session(%Session{} = session, dry_run?, acc) do
    rows = legacy_agent_rows(session.id)
    scanned = length(rows)

    cond do
      scanned == 0 ->
        Mix.shell().info("[#{session.id}] #{session.name || "(unnamed)"}: no legacy rows")
        Map.update!(acc, :scanned, &(&1 + scanned))

      true ->
        case load_turns(session) do
          {:ok, turn_index} ->
            {matched, updated} = apply_backfill(session, rows, turn_index, dry_run?)

            Mix.shell().info(
              "[#{session.id}] #{session.name || "(unnamed)"}: #{scanned} scanned, #{matched} matched, #{updated} updated"
            )

            acc
            |> Map.update!(:scanned, &(&1 + scanned))
            |> Map.update!(:matched, &(&1 + matched))
            |> Map.update!(:updated, &(&1 + updated))

          {:error, :not_found} ->
            Mix.shell().info(
              "[#{session.id}] #{session.name || "(unnamed)"}: no session file, skipping"
            )

            acc
            |> Map.update!(:scanned, &(&1 + scanned))
            |> Map.update!(:missing_file, &(&1 + 1))

          {:error, reason} ->
            Mix.shell().error(
              "[#{session.id}] failed to read session file: #{inspect(reason)}"
            )

            acc |> Map.update!(:scanned, &(&1 + scanned))
        end
    end
  end

  defp legacy_agent_rows(session_id) do
    from(m in Message,
      where: m.session_id == ^session_id,
      where: m.sender_role == "agent",
      where: is_nil(m.metadata) or fragment("?->'usage' IS NULL", m.metadata),
      select: %{id: m.id, source_uuid: m.source_uuid, inserted_at: m.inserted_at}
    )
    |> Repo.all()
  end

  # Loads the raw JSONL records (not the SessionReader-flattened maps) so we can
  # see `tokens` and ordering, and key by Gemini turn id.
  defp load_turns(%Session{} = session) do
    project_path = resolve_project_path(session)

    with {:ok, path} <- SessionReader.find_session_file(session.uuid, project_path),
         {:ok, body} <- File.read(path) do
      turns =
        body
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode/1)
        |> Enum.flat_map(fn
          {:ok, %{"id" => id, "timestamp" => ts} = turn} -> [Map.put(turn, "_ts_iso", ts) |> Map.put("_id", id)]
          _ -> []
        end)

      index =
        turns
        |> Enum.with_index()
        |> Map.new(fn {turn, idx} -> {turn["id"], {turn, idx, turns}} end)

      {:ok, index}
    end
  end

  defp apply_backfill(session, rows, turn_index, dry_run?) do
    Enum.reduce(rows, {0, 0}, fn row, {matched, updated} ->
      case Map.get(turn_index, row.source_uuid) do
        nil ->
          {matched, updated}

        {turn, idx, all_turns} ->
          metadata = build_metadata(turn, idx, all_turns)

          if dry_run? do
            Mix.shell().info(
              "  would update row #{row.id} (turn #{row.source_uuid}) with #{inspect(metadata)}"
            )

            {matched + 1, updated}
          else
            case update_metadata(row.id, metadata) do
              {1, _} ->
                {matched + 1, updated + 1}

              other ->
                Mix.shell().error(
                  "[#{session.id}] update_all returned #{inspect(other)} for row #{row.id}"
                )

                {matched + 1, updated}
            end
          end
      end
    end)
  end

  defp build_metadata(turn, idx, all_turns) do
    tokens = Map.get(turn, "tokens") || %{}

    input = Map.get(tokens, "input")
    output = Map.get(tokens, "output")
    total = Map.get(tokens, "total")

    duration_ms = duration_from_previous(turn, idx, all_turns)

    usage =
      %{}
      |> maybe_put("input_tokens", input)
      |> maybe_put("output_tokens", output)
      |> maybe_put("total_tokens", total)

    %{}
    |> maybe_put("usage", if(usage == %{}, do: nil, else: usage))
    |> maybe_put("duration_ms", duration_ms)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp duration_from_previous(_turn, 0, _all_turns), do: nil

  defp duration_from_previous(turn, idx, all_turns) do
    prev = Enum.at(all_turns, idx - 1)

    with %{} <- prev,
         {:ok, prev_ts, _} <- DateTime.from_iso8601(Map.get(prev, "timestamp", "")),
         {:ok, cur_ts, _} <- DateTime.from_iso8601(Map.get(turn, "timestamp", "")) do
      diff = DateTime.diff(cur_ts, prev_ts, :millisecond)
      if diff >= 0, do: diff, else: nil
    else
      _ -> nil
    end
  end

  defp resolve_project_path(%Session{project_id: nil}), do: nil

  defp resolve_project_path(%Session{project_id: pid}) do
    case Repo.get(EyeInTheSky.Projects.Project, pid) do
      %{path: path} when is_binary(path) -> path
      _ -> nil
    end
  end

  defp update_metadata(row_id, metadata) do
    from(m in Message, where: m.id == ^row_id)
    |> Repo.update_all(set: [metadata: metadata])
  end
end
