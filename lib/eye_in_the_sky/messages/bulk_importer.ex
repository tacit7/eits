defmodule EyeInTheSky.Messages.BulkImporter do
  @moduledoc """
  Shared import logic for session messages from any provider.

  Handles deduplication against existing DB records and persisting new ones.
  Provider-specific importers (Claude, Codex) prepare their messages and
  delegate here.

  Uses Repo.insert_all for efficient batch inserts. Per-row updates and inserts
  are executed independently (no enclosing transaction) so one bad row does not
  roll back other successful writes. Idempotency is guaranteed by the unique
  index on source_uuid combined with `on_conflict: :nothing`.
  """

  alias EyeInTheSky.Messages
  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.Repo

  require Logger

  @constraint_codes [:unique_violation, :foreign_key_violation, :check_violation]

  @doc """
  Imports a list of pre-parsed messages into the DB for the given session.

  Options:
    - `:provider` - (required) provider string, e.g. "claude" or "codex"
    - `:metadata_fn` - optional 1-arity function returning a metadata map or nil for a message

  Returns the count of successfully persisted or skipped messages (insert,
  update, fast-path skip, or DM dedup skip). Rows that conflict on source_uuid
  are counted as processed because they are already present in the DB.
  """
  @spec import_messages(list(map()), integer(), keyword()) :: integer()
  def import_messages(messages, session_id, opts) do
    provider = Keyword.fetch!(opts, :provider)
    metadata_fn = Keyword.get(opts, :metadata_fn, fn _msg -> nil end)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    messages_with_uuid = Enum.filter(messages, & &1.uuid)
    uuids = Enum.map(messages_with_uuid, & &1.uuid)
    existing = Messages.existing_source_uuids(session_id, uuids)

    # H3 fix: pre-fetch dedup data once before the per-message loop.
    # Replaces up to 3 per-message SELECTs with 2 batch queries + in-memory MapSet/Map lookups.
    #
    # dedup_agent_bodies: used for dm_already_recorded? (user msgs) and
    #   agent_reply_already_recorded? (non-user msgs). Window = 60s for live
    #   imports (conservative vs. the original 30s/60s split), 86400s for file imports.
    #
    # unlinked_candidates: keyed by {sender_role, body}; used in place of
    #   find_unlinked_import_candidate per-message SELECTs. Most-recent row wins.
    dedup_seconds = if Keyword.get(opts, :importing_from_file?, false), do: 86_400, else: 60

    context = %{
      session_id: session_id,
      now: now,
      provider: provider,
      metadata_fn: metadata_fn,
      existing_source_uuids: existing,
      import_opts: opts,
      dedup_agent_bodies: Messages.recent_agent_bodies_for_session(session_id, seconds: dedup_seconds),
      unlinked_candidates: Messages.unlinked_candidates_map_for_session(session_id)
    }

    # Separate messages into actions: updates (link existing), inserts (create new), skips
    # seen_agent_bodies tracks non-user message bodies already queued in this batch,
    # catching in-batch duplicates before they hit the DB (MapSet check is cheap-first).
    {updates, inserts, skip_count, _seen_agent_bodies} =
      Enum.reduce(messages_with_uuid, {[], [], 0, MapSet.new()}, fn msg, acc ->
        process_message(msg, context, acc)
      end)

    # Execute writes WITHOUT an enclosing transaction so one bad row does not
    # roll back other successful writes. Idempotency is guaranteed by the unique
    # index on source_uuid combined with on_conflict: :nothing.
    insert_count = run_inserts(inserts)
    update_count = run_updates(updates)

    # Return rows newly written + linked + skipped by pre-fetched dedup.
    # Race-conflict rows inside insert_all (rare: another session wrote the
    # same source_uuid concurrently) are NOT counted — they would be counted
    # as skips on the next import.
    insert_count + update_count + skip_count
  end

  defp run_inserts([]), do: 0

  defp run_inserts(inserts) do
    try do
      {count, _} =
        Repo.insert_all(Message, inserts,
          on_conflict: :nothing,
          conflict_target: :source_uuid
        )

      count
    rescue
      e in Postgrex.Error ->
        if is_map(e.postgres) and e.postgres.code in @constraint_codes do
          :telemetry.execute(
            [:eits, :messages, :bulk_import, :constraint_violation],
            %{batch_size: length(inserts)},
            %{code: e.postgres.code, table: "messages"}
          )

          Logger.warning(
            "BulkImporter: constraint violation on batch of #{length(inserts)}: #{inspect(e.postgres.code)}"
          )

          0
        else
          :telemetry.execute(
            [:eits, :messages, :bulk_import, :failed],
            %{batch_size: length(inserts)},
            %{error: inspect(e), table: "messages"}
          )

          Logger.error(
            "BulkImporter: systemic insert_all failure (batch=#{length(inserts)}): #{inspect(e)}"
          )

          reraise e, __STACKTRACE__
        end
    end
  end

  defp run_updates(updates) do
    Enum.count(updates, &run_single_update/1)
  end

  defp run_single_update({existing, update_attrs}) do
    case Messages.update_message(existing, update_attrs) do
      {:ok, _} ->
        true

      {:error, reason} ->
        Logger.debug(
          "BulkImporter: failed to link message #{existing.id}: #{inspect(reason)}"
        )

        false
    end
  rescue
    e in Postgrex.Error ->
      if is_map(e.postgres) and e.postgres.code in @constraint_codes do
        :telemetry.execute(
          [:eits, :messages, :bulk_import, :constraint_violation],
          %{batch_size: 1},
          %{code: e.postgres.code, table: "messages"}
        )

        Logger.warning(
          "BulkImporter: constraint violation updating message #{existing.id}: #{inspect(e.postgres.code)}"
        )

        false
      else
        :telemetry.execute(
          [:eits, :messages, :bulk_import, :update_failed],
          %{batch_size: 1},
          %{error: inspect(e), table: "messages"}
        )

        Logger.error(
          "BulkImporter: systemic update failure for message #{existing.id}: #{inspect(e)}"
        )

        reraise e, __STACKTRACE__
      end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp process_message(msg, context, {upd_acc, ins_acc, skip_count, seen_agent_bodies}) do
    %{
      session_id: session_id,
      now: now,
      provider: provider,
      metadata_fn: metadata_fn,
      existing_source_uuids: existing_source_uuids,
      dedup_agent_bodies: dedup_agent_bodies,
      unlinked_candidates: unlinked_candidates
    } = context

    cond do
      # Fast-path: if this source_uuid is already in the DB, skip the expensive body scan.
      MapSet.member?(existing_source_uuids, msg.uuid) ->
        {upd_acc, ins_acc, skip_count + 1, seen_agent_bodies}

      # H3 fix: was dm_already_recorded?/3 (per-message SELECT); now MapSet lookup.
      # Avoid double-rendering DMs. When a DM arrives, DMDelivery persists it
      # as sender_role: "agent" (inbound) and forwards it to the local CLI as
      # a user prompt; the session file then replays that prompt as role: "user".
      # Skip the import when a recent inbound DM with the same body already exists.
      msg.role == "user" and MapSet.member?(dedup_agent_bodies, msg.content) ->
        {upd_acc, ins_acc, skip_count + 1, seen_agent_bodies}

      # H3 fix: was agent_reply_already_recorded?/3 (per-message SELECT); now MapSet lookup.
      # seen_agent_bodies (in-batch, cheap) fires first; dedup_agent_bodies (pre-fetched DB
      # window) fires second to catch cross-batch races. User messages are excluded.
      msg.role != "user" and
          (MapSet.member?(seen_agent_bodies, msg.content) or
             MapSet.member?(dedup_agent_bodies, msg.content)) ->
        {upd_acc, ins_acc, skip_count + 1, seen_agent_bodies}

      true ->
        {sender_role, recipient_role, direction} = message_roles(msg.role)
        inserted_at = parse_timestamp(msg.timestamp, now)
        metadata = metadata_fn.(msg)

        # Track non-user bodies queued in this batch so subsequent messages
        # with the same body are caught by the MapSet check above (in-batch dedup).
        new_seen =
          if msg.role != "user",
            do: MapSet.put(seen_agent_bodies, msg.content),
            else: seen_agent_bodies

        # H3 fix: was Messages.find_unlinked_import_candidate/3 (per-message SELECT);
        # now a Map.get on the pre-fetched unlinked_candidates map.
        case Map.get(unlinked_candidates, {sender_role, msg.content}) do
          %Messages.Message{} = existing ->
            # Message exists but has no source_uuid; link it
            update_attrs = %{source_uuid: msg.uuid, updated_at: now}

            update_attrs =
              if metadata, do: Map.put(update_attrs, :metadata, metadata), else: update_attrs

            {[{existing, update_attrs} | upd_acc], ins_acc, skip_count, new_seen}

          nil ->
            # New message; prepare for batch insert
            new_message = %{
              uuid: Ecto.UUID.generate(),
              source_uuid: msg.uuid,
              session_id: session_id,
              sender_role: sender_role,
              recipient_role: recipient_role,
              direction: direction,
              body: msg.content,
              status: "delivered",
              provider: provider,
              metadata: metadata,
              inserted_at: inserted_at,
              updated_at: now
            }

            {upd_acc, [new_message | ins_acc], skip_count, new_seen}
        end
    end
  rescue
    e in Postgrex.Error ->
      Logger.warning("BulkImporter: Postgrex error processing message: #{inspect(e)}")
      {upd_acc, ins_acc, skip_count + 1, seen_agent_bodies}
  end

  defp message_roles("user"), do: {"user", "agent", "outbound"}
  defp message_roles(_role), do: {"agent", "user", "inbound"}

  defp parse_timestamp(timestamp, fallback) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> fallback
    end
  end

  defp parse_timestamp(_timestamp, fallback), do: fallback
end
