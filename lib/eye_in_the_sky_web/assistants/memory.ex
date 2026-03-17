defmodule EyeInTheSkyWeb.Assistants.Memory do
  @moduledoc """
  v1 memory layer for assistants, built on top of the existing notes system.
  No new tables. Disciplined use of notes with consistent conventions.

  ## Storage convention

  Memory notes use:
    - parent_type: "assistant"
    - parent_id: assistant.id (as string), or "global" for cross-assistant project memory
    - title: "[kind] optional short label" — e.g. "[summary] session 1150"
    - body: the actual memory content (markdown supported)

  ## Memory kinds

    - :summary     — rolling session summary written at session end
    - :preference  — how the assistant should behave (tone, output format, etc.)
    - :convention  — project conventions discovered during work
    - :decision    — significant decisions made during a run
    - :blocker     — recurring obstacles or known failure modes
    - :context     — project/domain context the assistant should retain

  ## Retrieval

  Retrieve by assistant_id, project scope, session, kind, or recency.
  Full-text search via the existing FTS5 module.
  Semantic (vector) search via pgvector cosine similarity when embeddings are available.

  ## When to write

  Assistants should write memory at:
    1. Session end — session summary note
    2. Project convention discovery — convention note
    3. Decision points requiring justification — decision note
    4. Recurring blockers — blocker note
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.{Notes, Repo}
  alias EyeInTheSky.Notes.Note
  alias EyeInTheSkyWeb.Search.PgSearch
  alias EyeInTheSky.Workers.EmbedNoteWorker

  @valid_kinds ~w(summary preference convention decision blocker context)
  @default_limit 20

  @doc """
  Writes a memory note for an assistant and enqueues an embedding job.

  ## Options
    - :kind — one of #{Enum.join(@valid_kinds, ", ")} (default: :context)
    - :label — short label appended to title (optional)
    - :session_id — link memory to a specific session (optional)
    - :project_id — scope to a project (optional; stored in body preamble)

  ## Examples

      Memory.write(assistant, "Always use snake_case for variable names",
        kind: :convention, label: "naming")

      Memory.write(assistant, "Decided to use scoped notes instead of vector DB",
        kind: :decision, label: "memory system")
  """
  def write(assistant_or_id, body, opts \\ []) do
    assistant_id = extract_id(assistant_or_id)
    kind         = Keyword.get(opts, :kind, :context) |> to_string()
    label        = Keyword.get(opts, :label)
    session_id   = Keyword.get(opts, :session_id)

    title = build_title(kind, label, session_id)

    # Prepend session_id metadata line so list/2 can filter by session.
    # Format: "session_id: <id>\n\n<body>" — keeps the body human-readable
    # while being reliably matchable via SQL LIKE.
    full_body =
      if session_id, do: "session_id: #{session_id}\n\n#{body}", else: body

    result =
      Notes.create_note(%{
        parent_type: "assistant",
        parent_id:   to_string(assistant_id),
        title:       title,
        body:        full_body
      })

    case result do
      {:ok, note} ->
        # Fire-and-forget embedding — FTS is the fallback if this fails
        Oban.insert(EmbedNoteWorker.new(%{"note_id" => note.id}))
        {:ok, note}

      error ->
        error
    end
  end

  @doc """
  Lists memory notes for an assistant, newest first.

  ## Options
    - :kind — filter by memory kind
    - :limit — max results (default #{@default_limit})
    - :session_id — filter by originating session
  """
  def list(assistant_or_id, opts \\ []) do
    assistant_id = extract_id(assistant_or_id)
    kind         = Keyword.get(opts, :kind)
    limit        = Keyword.get(opts, :limit, @default_limit)
    session_id   = Keyword.get(opts, :session_id)

    Note
    |> where([n], n.parent_type == "assistant" and n.parent_id == ^to_string(assistant_id))
    |> then(fn q ->
      if kind do
        prefix = "[#{kind}]"
        where(q, [n], like(n.title, ^"#{prefix}%"))
      else
        q
      end
    end)
    |> then(fn q ->
      if session_id do
        where(q, [n], like(n.body, ^"%session_id: #{session_id}%"))
      else
        q
      end
    end)
    |> order_by([n], desc: n.created_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns the most recent memory of a specific kind.
  """
  def latest(assistant_or_id, kind) do
    assistant_id = extract_id(assistant_or_id)
    prefix = "[#{kind}]"

    Note
    |> where([n], n.parent_type == "assistant" and n.parent_id == ^to_string(assistant_id))
    |> where([n], like(n.title, ^"#{prefix}%"))
    |> order_by([n], desc: n.created_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Full-text search across an assistant's memory notes, with semantic reranking
  via reciprocal rank fusion when vector embeddings are available.
  """
  def search(assistant_or_id, query) when is_binary(query) do
    assistant_id = extract_id(assistant_or_id)
    parent_id_str = to_string(assistant_id)

    extra_where =
      dynamic([n], n.parent_type == "assistant" and n.parent_id == ^parent_id_str)

    fts_results =
      PgSearch.search_for(query,
        table: "notes",
        schema: Note,
        search_columns: ["title", "body"],
        extra_where: extra_where,
        order_by: [desc: :created_at]
      )

    case embed_query(query) do
      {:ok, query_vector} ->
        vec_results = semantic_search(assistant_or_id, query_vector, limit: 20)
        reciprocal_rank_fusion(fts_results, vec_results)

      {:error, _} ->
        fts_results
    end
  end

  @doc """
  Cosine-similarity vector search for an assistant's memory notes.
  Returns notes ordered by closest embedding distance.

  ## Options
    - :limit — max results (default #{@default_limit})
  """
  def semantic_search(assistant_or_id, query_vector, opts \\ []) do
    assistant_id = extract_id(assistant_or_id)
    limit        = Keyword.get(opts, :limit, @default_limit)
    parent_id_str = to_string(assistant_id)

    Note
    |> where([n], n.parent_type == "assistant" and n.parent_id == ^parent_id_str)
    |> where([n], not is_nil(n.embedding))
    |> order_by([n], fragment("? <=> ?", n.embedding, ^query_vector))
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Writes a session summary memory note. Call at session end.
  """
  def write_session_summary(assistant_or_id, session_id, summary_body) do
    write(assistant_or_id, summary_body,
      kind: :summary,
      label: "session #{session_id}",
      session_id: session_id
    )
  end

  @doc """
  Returns a condensed memory context string for prompt injection.
  Pulls the most recent notes of each kind, formatted for inclusion in a system prompt.

  ## Example output

      ## Assistant Memory

      **Conventions**
      - Always use snake_case for variable names
      - Prefer Ecto queries over raw SQL

      **Recent Summary**
      Worked on authentication refactor. Decided to use passkeys only.

      **Blockers**
      - mix compile fails with --warnings-as-errors due to pre-existing CodeReloader warning
  """
  def build_context(assistant_or_id, opts \\ []) do
    assistant_id = extract_id(assistant_or_id)
    limit        = Keyword.get(opts, :limit, 3)

    kinds = [:convention, :preference, :summary, :blocker, :decision]

    sections =
      kinds
      |> Enum.map(fn kind ->
        notes =
          Note
          |> where([n], n.parent_type == "assistant" and n.parent_id == ^to_string(assistant_id))
          |> where([n], like(n.title, ^"[#{kind}]%"))
          |> order_by([n], desc: n.created_at)
          |> limit(^limit)
          |> Repo.all()

        {kind, notes}
      end)
      |> Enum.reject(fn {_kind, notes} -> notes == [] end)

    if sections == [] do
      nil
    else
      body =
        sections
        |> Enum.map(fn {kind, notes} ->
          heading = kind |> to_string() |> String.capitalize() |> then(&"**#{&1}**")

          entries =
            notes
            |> Enum.map(fn n -> "- #{String.trim(n.body)}" end)
            |> Enum.join("\n")

          "#{heading}\n#{entries}"
        end)
        |> Enum.join("\n\n")

      "## Assistant Memory\n\n#{body}"
    end
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  defp extract_id(%{id: id}), do: id
  defp extract_id(id) when is_integer(id), do: id
  defp extract_id(id) when is_binary(id), do: id

  defp build_title(kind, nil, nil),        do: "[#{kind}]"
  defp build_title(kind, label, nil),      do: "[#{kind}] #{label}"
  defp build_title(kind, nil, session_id), do: "[#{kind}] session #{session_id}"
  defp build_title(kind, label, _),        do: "[#{kind}] #{label}"

  # Embed a query string for semantic search, using same model as notes.
  # Returns {:ok, vector} or {:error, reason}.
  defp embed_query(text) do
    api_key = Application.get_env(:eye_in_the_sky_web, :openai_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, :no_api_key}
    else
      body = Jason.encode!(%{model: "text-embedding-3-small", input: text})

      request =
        Finch.build(
          :post,
          "https://api.openai.com/v1/embeddings",
          [
            {"Authorization", "Bearer #{api_key}"},
            {"Content-Type", "application/json"}
          ],
          body
        )

      case Finch.request(request, EyeInTheSky.Finch) do
        {:ok, %Finch.Response{status: 200, body: resp_body}} ->
          case Jason.decode(resp_body) do
            {:ok, %{"data" => [%{"embedding" => vector} | _]}} ->
              {:ok, Pgvector.new(vector)}

            _ ->
              {:error, :parse_error}
          end

        _ ->
          {:error, :api_error}
      end
    end
  end

  # Reciprocal rank fusion of FTS and vector results.
  # RRF score = 1/(k + rank), k=60 is standard.
  defp reciprocal_rank_fusion(fts_results, vec_results, k \\ 60) do
    fts_scores =
      fts_results
      |> Enum.with_index(1)
      |> Map.new(fn {note, rank} -> {note.id, 1.0 / (k + rank)} end)

    vec_scores =
      vec_results
      |> Enum.with_index(1)
      |> Map.new(fn {note, rank} -> {note.id, 1.0 / (k + rank)} end)

    all_notes =
      (fts_results ++ vec_results)
      |> Enum.uniq_by(& &1.id)

    all_notes
    |> Enum.map(fn note ->
      score = Map.get(fts_scores, note.id, 0.0) + Map.get(vec_scores, note.id, 0.0)
      {score, note}
    end)
    |> Enum.sort_by(fn {score, _} -> score end, :desc)
    |> Enum.map(fn {_, note} -> note end)
  end
end
