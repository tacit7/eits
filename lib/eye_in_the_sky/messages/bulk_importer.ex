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

    context = %{
      session_id: session_id,
      now: now,
      provider: provider,
      metadata_fn: metadata_fn,
      existing_source_uuids: existing,
      import_opts: opts
    }

    # Separate messages into actions: updates (link existing), inserts (create new), skips
    {updates, inserts, skip_count} =
      Enum.reduce(messages_with_uuid, {[], [], 0}, fn msg, {upd_acc, ins_acc, skip_count} ->
        process_message(msg, context, upd_acc, ins_acc, skip_count)
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

  defp process_message(msg, context, upd_acc, ins_acc, skip_count) do
    %{
      session_id: session_id,
      now: now,
      provider: provider,
      metadata_fn: metadata_fn,
      existing_source_uuids: existing_source_uuids,
      import_opts: import_opts
    } = context

    cond do
      # Fast-path: if this source_uuid is already in the DB, skip the expensive body scan.
      MapSet.member?(existing_source_uuids, msg.uuid) ->
        {upd_acc, ins_acc, skip_count + 1}

      # Avoid double-rendering DMs. When a DM arrives, DMDelivery persists it
      # as sender_role: "agent" (inbound) and forwards it to the local CLI as
      # a user prompt; the session file then replays that prompt as
      # role: "user". The find_unlinked_import_candidate lookup below only matches on
      # sender_role, so the inbound "agent" row is invisible to it and a
      # second outbound/user row gets created with the same body, making the
      # DM render twice in the chat (once received, once "sent"). Skip the
      # import when a recent inbound DM with the same body already exists.
      msg.role == "user" and dm_already_recorded?(session_id, msg.content, import_opts) ->
        {upd_acc, ins_acc, skip_count + 1}

      # Avoid double-rendering the final agent message. AgentWorker persists
      # the assistant reply via record_incoming_reply using the SDK result UUID
      # as source_uuid. BulkImporter later runs for the same JSONL file and
      # sees the per-message JSONL UUID — a different value. The fast-path UUID
      # check misses, and find_unlinked_import_candidate requires
      # source_uuid IS NULL so it also misses, causing a second insert with
      # the JSONL UUID. Skip when a recent agent message with the same body
      # already exists. Use a 120 s window — long enough to cover the
      # AgentWorker → agent_stopped → BulkImporter race, short enough to
      # never false-positive on legitimately repeated agent output.
      msg.role != "user" and
          not Keyword.get(import_opts, :importing_from_file?, false) and
          agent_reply_already_recorded?(session_id, msg.content) ->
        {upd_acc, ins_acc, skip_count + 1}

      true ->
        {sender_role, recipient_role, direction} = message_roles(msg.role)
        inserted_at = parse_timestamp(msg.timestamp, now)
        metadata = metadata_fn.(msg)

        case Messages.find_unlinked_import_candidate(session_id, sender_role, msg.content) do
          {:ok, existing} ->
            # Message exists but has no source_uuid; link it
            update_attrs = %{source_uuid: msg.uuid, updated_at: now}

            update_attrs =
              if metadata, do: Map.put(update_attrs, :metadata, metadata), else: update_attrs

            {[{existing, update_attrs} | upd_acc], ins_acc, skip_count}

          :not_found ->
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

            {upd_acc, [new_message | ins_acc], skip_count}
        end
    end
  rescue
    e in Postgrex.Error ->
      Logger.warning("BulkImporter: Postgrex error processing message: #{inspect(e)}")
      {upd_acc, ins_acc, skip_count + 1}
  end

  defp dm_already_recorded?(session_id, body, opts) do
    seconds = if Keyword.get(opts, :importing_from_file?, false), do: 86_400, else: 60

    case Messages.find_recent_dm(session_id, body, seconds: seconds) do
      nil -> false
      _msg -> true
    end
  end

  # Checks whether an agent reply with the same body was recently persisted by
  # record_incoming_reply (AgentWorker on_result_received). That path stores
  # the SDK result UUID as source_uuid, which differs from the per-message
  # JSONL UUID that BulkImporter uses, so the fast-path UUID set check always
  # misses. A 120 s window covers the AgentWorker → agent_stopped →
  # BulkImporter pipeline without false-positiving on legitimately repeated
  # agent output.
  defp agent_reply_already_recorded?(session_id, body) do
    case Messages.find_recent_dm(session_id, body, seconds: 120) do
      nil -> false
      _msg -> true
    end
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
