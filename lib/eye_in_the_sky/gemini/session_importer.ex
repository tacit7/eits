defmodule EyeInTheSky.Gemini.SessionImporter do
  @moduledoc """
  Imports messages from Gemini CLI session JSONL files into the database.

  Thin adapter over `EyeInTheSky.Messages.BulkImporter` — handles
  Gemini-specific file reading via `Gemini.SessionReader` and delegates
  shared import / dedup logic.
  """

  alias EyeInTheSky.Gemini.Pricing
  alias EyeInTheSky.Gemini.SessionReader
  alias EyeInTheSky.Messages
  alias EyeInTheSky.Messages.BulkImporter

  @doc """
  Read messages from the Gemini session file that came after the last
  imported message and persist any not already in the DB (matched by
  source_uuid).

  Returns `{:ok, %{inserted, updated, skipped}}` on success.
  """
  @spec sync(String.t(), String.t() | nil, integer()) ::
          {:ok, %{inserted: integer(), updated: integer(), skipped: integer()}}
          | {:error, term()}
  def sync(session_uuid, project_path, session_id) do
    last_uuid = Messages.get_last_source_uuid(session_id)

    with {:ok, messages} <-
           SessionReader.read_messages_after_uuid(session_uuid, project_path, last_uuid) do
      {:ok, import_messages(messages, session_id)}
    end
  end

  @doc """
  Persist a pre-parsed list of messages.

  Skips rows whose `source_uuid` already exists. Returns the per-row
  counts produced by `BulkImporter`.
  """
  @spec import_messages(list(map()), integer()) ::
          %{inserted: integer(), updated: integer(), skipped: integer()}
  def import_messages(messages, session_id) do
    BulkImporter.import_messages(messages, session_id,
      provider: "gemini",
      importing_from_file?: true,
      metadata_fn: &build_metadata/1
    )
  end

  # Convert a SessionReader-shaped message into the metadata map persisted
  # alongside the message row. Mirrors the live StreamHandler's stats_to_map/2
  # output: usage block (with input/output/total_tokens) plus total_cost_usd
  # and model_usage so the DM metrics footer renders identically for
  # streamed-now vs reloaded-from-file turns.
  defp build_metadata(%{role: "assistant"} = msg) do
    tokens = msg[:usage] || %{}
    model = msg[:model]

    input = Map.get(tokens, "input")
    output = Map.get(tokens, "output")
    total = Map.get(tokens, "total")

    cost = Pricing.cost(model, input, output)
    model_usage = Pricing.model_usage(model, input, output)

    usage = %{}
    usage = if input, do: Map.put(usage, "input_tokens", input), else: usage
    usage = if output, do: Map.put(usage, "output_tokens", output), else: usage
    usage = if total, do: Map.put(usage, "total_tokens", total), else: usage

    md =
      %{}
      |> maybe_put("usage", if(usage == %{}, do: nil, else: usage))
      |> maybe_put("total_cost_usd", cost)
      |> maybe_put("model_usage", model_usage)

    if md == %{}, do: nil, else: md
  end

  defp build_metadata(_msg), do: nil

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
end
