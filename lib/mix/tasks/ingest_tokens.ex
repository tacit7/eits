defmodule Mix.Tasks.IngestTokens do
  @moduledoc """
  Ingests token usage from Claude JSONL session files into session_metrics.

  ## Usage

      mix ingest_tokens              # Process all unprocessed sessions
      mix ingest_tokens --force      # Re-process all sessions (overwrite existing)
      mix ingest_tokens --session UUID  # Process a single session by UUID
  """

  use Mix.Task

  alias EyeInTheSky.Metrics.TokenIngestion

  @shortdoc "Ingest token usage from Claude JSONL files into session_metrics"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [force: :boolean, session: :string],
        aliases: [f: :force, s: :session]
      )

    if opts[:session] do
      ingest_single(opts[:session])
    else
      ingest_all(force: opts[:force] || false)
    end
  end

  defp ingest_single(uuid) do
    Mix.shell().info("Ingesting session #{uuid}...")

    case TokenIngestion.ingest_session(uuid) do
      :ok ->
        Mix.shell().info("Done.")

      {:error, reason} ->
        Mix.shell().error("Failed: #{inspect(reason)}")
    end
  end

  defp ingest_all(opts) do
    force = Keyword.get(opts, :force, false)
    mode = if force, do: "force", else: "incremental"
    Mix.shell().info("Ingesting token usage (#{mode})...")

    {ingested, skipped, errors} =
      TokenIngestion.ingest_all(force: force)

    Mix.shell().info("""
    Done.
      Ingested: #{ingested}
      Skipped:  #{skipped}
      Errors:   #{errors}
    """)
  end
end
