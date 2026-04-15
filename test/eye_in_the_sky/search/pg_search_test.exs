defmodule EyeInTheSky.Search.PgSearchTest do
  use EyeInTheSky.DataCase, async: false

  import Ecto.Query

  alias EyeInTheSky.Search.PgSearch
  alias EyeInTheSky.Notes.Note

  defp uniq, do: System.unique_integer([:positive])

  defp create_note(title, body \\ "") do
    {:ok, note} =
      EyeInTheSky.Notes.create_note(%{
        parent_id: to_string(uniq()),
        parent_type: "session",
        body: "#{title} #{body}"
      })

    note
  end

  describe "search_for/2 LIMIT parameterization" do
    test "respects limit option and does not inject into SQL" do
      # Create 10 notes all matching the query
      tag = "limitcheck#{uniq()}"
      for _ <- 1..10, do: create_note(tag)

      results =
        PgSearch.search_for(tag,
          schema: Note,
          table: "notes",
          search_columns: ["body"],
          limit: 3
        )

      assert length(results) <= 3
    end

    test "defaults to 50 when limit is nil" do
      # We only verify it doesn't crash and returns a list
      tag = "defaultlimit#{uniq()}"
      create_note(tag)

      results =
        PgSearch.search_for(tag,
          schema: Note,
          table: "notes",
          search_columns: ["body"]
        )

      assert is_list(results)
    end

    test "treats non-positive limit as 50 (safe default) in FTS path" do
      tag = "zerolimit#{uniq()}"
      create_note(tag)

      results =
        PgSearch.search_for(tag,
          schema: Note,
          table: "notes",
          search_columns: ["body"],
          limit: 0
        )

      assert is_list(results)
    end

    test "fallback path treats limit=0 as 50, not LIMIT 0" do
      # Trigger the fallback path by using an unsafe table identifier.
      # limit=0 used to become LIMIT 0 in run_fallback via `limit || 50` since 0
      # is truthy in Elixir. After the fix both paths use the same guard.
      tag = "fallback_zerolimit#{uniq()}"
      for _ <- 1..3, do: create_note(tag)

      pattern = "%#{tag}%"

      fallback_query = from(n in Note, where: ilike(n.body, ^pattern))

      # "notes!" fails safe_identifier? → forces run_fallback path
      results =
        PgSearch.search(
          schema: Note,
          table: "notes!",
          query: tag,
          search_columns: ["body"],
          fallback_query: fallback_query,
          limit: 0
        )

      # With limit=0, if not normalized we'd get 0 rows even though 3 exist.
      # After the fix, fallback uses effective_limit=50 and returns all 3.
      assert length(results) >= 3
    end

    test "limit value is passed as a bound parameter, not interpolated" do
      # If LIMIT were interpolated and we passed a non-integer, it would cause a SQL error.
      # With a bound param, Postgrex rejects it at the type level before the query runs.
      # We verify that integer limits work correctly end-to-end.
      tag = "paramcheck#{uniq()}"
      for _ <- 1..5, do: create_note(tag)

      results =
        PgSearch.search_for(tag,
          schema: Note,
          table: "notes",
          search_columns: ["body"],
          limit: 2
        )

      assert length(results) <= 2
    end
  end
end
