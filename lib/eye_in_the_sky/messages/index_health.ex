defmodule EyeInTheSky.Messages.IndexHealth do
  @moduledoc "Reports Postgres index validity for the messages table."

  alias EyeInTheSky.Repo

  @type index_row :: %{name: String.t(), valid: boolean(), ready: boolean()}

  @doc "Returns {:ok, [index_row]} or {:error, reason}."
  @spec list_message_indexes() :: {:ok, [index_row]} | {:error, term()}
  def list_message_indexes do
    query = """
    SELECT c.relname::text AS name,
           i.indisvalid  AS valid,
           i.indisready  AS ready
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
    WHERE i.indrelid = 'messages'::regclass
    ORDER BY c.relname
    """

    case Repo.query(query) do
      {:ok, %{rows: rows}} ->
        {:ok, Enum.map(rows, fn [name, valid, ready] -> %{name: name, valid: valid, ready: ready} end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Returns the list of invalid indexes (empty list when healthy)."
  @spec invalid_indexes() :: [index_row]
  def invalid_indexes do
    case list_message_indexes() do
      {:ok, rows} -> Enum.filter(rows, &(&1.valid == false or &1.ready == false))
      {:error, _} -> []
    end
  end
end
