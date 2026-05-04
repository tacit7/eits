defmodule EyeInTheSky.Messages.Search do
  @moduledoc false

  import Ecto.Query, warn: false
  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.Repo

  @doc """
  Cross-session full-text search across session messages.

  Options:
    - `:session_id` - integer session ID to scope results (optional)
    - `:limit` - max results to return (default 10, max 100)
    - `:include_archived` - include messages from archived sessions (default false)

  Returns list of maps with keys: id, session_id, session_uuid, sender_role, body_excerpt, inserted_at.
  Uses the GIN index on messages_body_fts for efficient FTS. Returns [] when no FTS match.
  """
  @spec search_messages(String.t(), keyword()) :: [map()]
  def search_messages(query, opts \\ [])

  def search_messages(query, opts) when is_binary(query) and query != "" do
    limit = min(Keyword.get(opts, :limit, 10), 100)
    session_id = Keyword.get(opts, :session_id)
    include_archived = Keyword.get(opts, :include_archived, false)

    base =
      from(m in Message,
        join: s in EyeInTheSky.Sessions.Session,
        on: m.session_id == s.id,
        where: not is_nil(m.session_id),
        where: m.sender_role in ["user", "agent", "assistant"],
        order_by: [desc: m.inserted_at],
        limit: ^limit,
        select: %{
          id: m.id,
          session_id: m.session_id,
          session_uuid: s.uuid,
          session_name: s.name,
          sender_role: m.sender_role,
          body: m.body,
          inserted_at: m.inserted_at
        }
      )

    base =
      if include_archived do
        base
      else
        where(base, [_m, s], is_nil(s.archived_at))
      end

    base =
      if session_id do
        where(base, [m], m.session_id == ^session_id)
      else
        base
      end

    fts_query =
      where(
        base,
        [m],
        fragment(
          "to_tsvector('english', COALESCE(?, '')) @@ plainto_tsquery('english', ?)",
          m.body,
          ^query
        )
      )

    # No ILIKE fallback: a %term% pattern requires a full table scan on messages
    # (no trigram index). FTS returning [] is a real miss — don't hide it with
    # a slow fallback that makes the empty case the most expensive case.
    results = Repo.all(fts_query)

    Enum.map(results, fn row ->
      %{
        id: row.id,
        session_id: row.session_id,
        session_uuid: row.session_uuid,
        session_name: row.session_name,
        sender_role: row.sender_role,
        body_excerpt: String.slice(row.body || "", 0, 200),
        inserted_at: row.inserted_at
      }
    end)
  end

  def search_messages(_query, _opts), do: []
end
