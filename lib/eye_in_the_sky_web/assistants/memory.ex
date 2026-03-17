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

  ## When to write

  Assistants should write memory at:
    1. Session end — session summary note
    2. Project convention discovery — convention note
    3. Decision points requiring justification — decision note
    4. Recurring blockers — blocker note
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.{Notes, Repo}
  alias EyeInTheSkyWeb.Notes.Note
  alias EyeInTheSkyWeb.Search.FTS5

  @valid_kinds ~w(summary preference convention decision blocker context)
  @default_limit 20

  @doc """
  Writes a memory note for an assistant.

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

    Notes.create_note(%{
      parent_type: "assistant",
      parent_id:   to_string(assistant_id),
      title:       title,
      body:        body
    })
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
  Full-text search across an assistant's memory notes.
  """
  def search(assistant_or_id, query) when is_binary(query) do
    assistant_id = extract_id(assistant_or_id)

    extra_where =
      dynamic([n], n.parent_type == "assistant" and n.parent_id == ^to_string(assistant_id))

    FTS5.search_for(query,
      table: "notes",
      schema: Note,
      search_columns: ["title", "body"],
      sql_filter: "AND s.parent_type = 'assistant' AND s.parent_id = $2",
      sql_params: [to_string(assistant_id)],
      extra_where: extra_where,
      order_by: [desc: :created_at]
    )
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
end
