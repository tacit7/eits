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

  Returns list of maps with keys: id, session_id, session_uuid, sender_role, body_excerpt, inserted_at.
  Uses the GIN index on messages_body_fts for efficient FTS. Falls back to ILIKE on error.
  """
  @spec search_messages(String.t(), keyword()) :: [map()]
  def search_messages(query, opts \\ [])

  def search_messages(query, opts) when is_binary(query) and query != "" do
    limit = min(Keyword.get(opts, :limit, 10), 100)
    session_id = Keyword.get(opts, :session_id)

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

    results =
      case Repo.all(fts_query) do
        [] ->
          pattern = "%#{query}%"
          ilike_query = where(base, [m], ilike(m.body, ^pattern))
          Repo.all(ilike_query)

        rows ->
          rows
      end

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
