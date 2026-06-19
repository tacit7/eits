defmodule EyeInTheSkyWeb.Helpers.SessionFiltersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Helpers.SessionFilters

  # ---------------------------------------------------------------------------
  # Test helpers
  # ---------------------------------------------------------------------------

  # ISO8601 format (T separator) — used by sort_datetime/1 via DateTime.from_iso8601
  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp ago_iso(seconds),
    do: DateTime.utc_now() |> DateTime.add(-seconds, :second) |> DateTime.to_iso8601()

  # Space-separated format expected by VH.coerce_datetime/parse_datetime
  # ("YYYY-MM-DD HH:MM:SS") — this is how Ecto serializes datetimes as strings
  defp now_db do
    DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.to_string() |> String.slice(0..18)
  end

  defp ago_db(seconds) do
    DateTime.utc_now()
    |> DateTime.add(-seconds, :second)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
    |> String.slice(0..18)
  end

  defp session(overrides \\ %{}) do
    Map.merge(
      %{
        id: 1,
        uuid: "abc-123",
        name: "test session",
        status: "working",
        archived_at: nil,
        ended_at: nil,
        started_at: now_iso(),
        last_activity_at: now_iso(),
        model: "claude-sonnet-4-6",
        model_name: nil,
        agent: %{
          uuid: "agent-uuid",
          id: 1,
          description: "test agent",
          project_name: "test project",
          agent_definition: nil
        }
      },
      overrides
    )
  end

  # ---------------------------------------------------------------------------
  # filter_and_sort_sessions/1
  # Note: search_match?/2 calls String.downcase(session.id) directly, so
  # session.id must be a string (or nil) for non-empty search queries.
  # filter_agents_by_search/2 handles this correctly via to_string_or_empty/1.
  # ---------------------------------------------------------------------------

  describe "filter_and_sort_sessions/1" do
    test "empty sessions list returns empty list" do
      result = SessionFilters.filter_and_sort_sessions(%{sessions: []})
      assert result == []
    end

    test "returns all sessions when search_query is empty" do
      s1 = session(%{id: 1, name: "alpha"})
      s2 = session(%{id: 2, name: "beta"})

      result =
        SessionFilters.filter_and_sort_sessions(%{sessions: [s1, s2], search_query: ""})

      assert length(result) == 2
    end

    test "filters by search_query matching session name" do
      # session.id must be nil/string — search_match? calls String.downcase(id) directly
      match = session(%{id: nil, name: "deployment runner"})
      no_match = session(%{id: nil, name: "unrelated"})

      result =
        SessionFilters.filter_and_sort_sessions(%{
          sessions: [match, no_match],
          search_query: "deployment"
        })

      assert [^match] = result
    end

    test "returns empty list when search_query matches nothing" do
      s = session(%{id: nil, name: "my session"})

      result =
        SessionFilters.filter_and_sort_sessions(%{
          sessions: [s],
          search_query: "zzznomatch"
        })

      assert result == []
    end

    test "status_filter 'all' returns every session" do
      active = session(%{status: "working", ended_at: nil})
      done = session(%{id: 2, status: "completed", ended_at: now_iso()})

      result =
        SessionFilters.filter_and_sort_sessions(%{
          sessions: [active, done],
          status_filter: "all"
        })

      assert length(result) == 2
    end

    test "status_filter 'active' excludes completed sessions" do
      active = session(%{id: 1, status: "working", ended_at: nil})
      done = session(%{id: 2, status: "completed", ended_at: now_iso()})

      result =
        SessionFilters.filter_and_sort_sessions(%{
          sessions: [active, done],
          status_filter: "active"
        })

      assert [^active] = result
    end

    test "status_filter 'active' excludes discovered sessions" do
      active = session(%{id: 1, status: "idle", ended_at: nil})
      discovered = session(%{id: 2, status: "discovered", ended_at: nil})

      result =
        SessionFilters.filter_and_sort_sessions(%{
          sessions: [active, discovered],
          status_filter: "active"
        })

      assert [^active] = result
    end

    test "status_filter 'completed' returns only sessions with ended_at set" do
      active = session(%{id: 1, status: "working", ended_at: nil})
      done = session(%{id: 2, status: "completed", ended_at: now_iso()})

      result =
        SessionFilters.filter_and_sort_sessions(%{
          sessions: [active, done],
          status_filter: "completed"
        })

      assert [^done] = result
    end

    test "sorts by recent (started_at) descending by default" do
      # VH.coerce_datetime/parse_datetime expects space-separated format "YYYY-MM-DD HH:MM:SS"
      old = session(%{id: 1, started_at: ago_db(3600)})
      new = session(%{id: 2, started_at: now_db()})

      result =
        SessionFilters.filter_and_sort_sessions(%{
          sessions: [old, new],
          search_query: ""
        })

      assert [first | _] = result
      assert first.id == 2
    end

    test "missing search_query key treated as empty (no filter)" do
      s1 = session(%{id: 1})
      s2 = session(%{id: 2})

      result = SessionFilters.filter_and_sort_sessions(%{sessions: [s1, s2]})
      assert length(result) == 2
    end
  end

  # ---------------------------------------------------------------------------
  # filter_agents_by_status/2
  # ---------------------------------------------------------------------------

  describe "filter_agents_by_status/2" do
    test "'working' keeps working/idle/waiting/compacting sessions with nil archived_at" do
      keep =
        for status <- ["working", "idle", "waiting", "compacting"] do
          session(%{id: status, status: status, archived_at: nil})
        end

      drop =
        session(%{id: "completed", status: "completed", archived_at: nil})

      result = SessionFilters.filter_agents_by_status(keep ++ [drop], "working")
      assert length(result) == 4
      refute Enum.any?(result, &(&1.status == "completed"))
    end

    test "'working' excludes archived sessions even if status is working" do
      archived = session(%{id: 1, status: "working", archived_at: now_iso()})
      result = SessionFilters.filter_agents_by_status([archived], "working")
      assert result == []
    end

    test "'active' behaves identically to 'working'" do
      s = session(%{status: "idle", archived_at: nil})
      assert SessionFilters.filter_agents_by_status([s], "active") == [s]
    end

    test "'active' excludes archived sessions" do
      s = session(%{status: "idle", archived_at: now_iso()})
      assert SessionFilters.filter_agents_by_status([s], "active") == []
    end

    test "'completed' keeps only completed non-archived sessions" do
      done = session(%{id: 1, status: "completed", archived_at: nil})
      active = session(%{id: 2, status: "working", archived_at: nil})
      archived_done = session(%{id: 3, status: "completed", archived_at: now_iso()})

      result = SessionFilters.filter_agents_by_status([done, active, archived_done], "completed")
      assert [^done] = result
    end

    test "'archived' returns only sessions with non-nil archived_at" do
      archived = session(%{id: 1, archived_at: now_iso()})
      not_archived = session(%{id: 2, archived_at: nil})

      result = SessionFilters.filter_agents_by_status([archived, not_archived], "archived")
      assert [^archived] = result
    end

    test "unknown filter passes all sessions through" do
      s1 = session(%{id: 1})
      s2 = session(%{id: 2})
      result = SessionFilters.filter_agents_by_status([s1, s2], "whatever")
      assert result == [s1, s2]
    end

    test "'working' keeps sessions with nil status" do
      s = session(%{status: nil, archived_at: nil})
      result = SessionFilters.filter_agents_by_status([s], "working")
      assert [^s] = result
    end
  end

  # ---------------------------------------------------------------------------
  # filter_agents_by_search/2
  # ---------------------------------------------------------------------------

  describe "filter_agents_by_search/2" do
    test "empty query returns all sessions" do
      sessions = [session(%{id: 1}), session(%{id: 2})]
      assert SessionFilters.filter_agents_by_search(sessions, "") == sessions
    end

    test "nil query returns all sessions" do
      sessions = [session(%{id: 1})]
      assert SessionFilters.filter_agents_by_search(sessions, nil) == sessions
    end

    test "whitespace-only query returns all sessions" do
      sessions = [session(%{id: 1})]
      assert SessionFilters.filter_agents_by_search(sessions, "   ") == sessions
    end

    test "matches by session name (case-insensitive)" do
      match = session(%{name: "Deploy Pipeline"})
      no_match = session(%{id: 2, name: "unrelated"})

      result = SessionFilters.filter_agents_by_search([match, no_match], "deploy")
      assert [^match] = result
    end

    test "matches by session uuid" do
      target = session(%{uuid: "deadbeef-0000-0000-0000-000000000000"})
      other = session(%{id: 2, uuid: "aaaaaaaa-0000-0000-0000-000000000000"})

      result = SessionFilters.filter_agents_by_search([target, other], "deadbeef")
      assert [^target] = result
    end

    test "matches by agent description" do
      agent = %{
        uuid: "u1",
        id: 1,
        description: "code reviewer agent",
        project_name: nil,
        agent_definition: nil
      }

      match = session(%{agent: agent})
      no_match = session(%{id: 2})

      result = SessionFilters.filter_agents_by_search([match, no_match], "reviewer")
      assert [^match] = result
    end

    test "matches by agent project_name" do
      agent = %{
        uuid: "u1",
        id: 1,
        description: nil,
        project_name: "Payments Platform",
        agent_definition: nil
      }

      match = session(%{agent: agent})
      no_match = session(%{id: 2})

      result = SessionFilters.filter_agents_by_search([match, no_match], "payments")
      assert [^match] = result
    end

    test "no match returns empty list" do
      s = session(%{name: "alpha"})
      result = SessionFilters.filter_agents_by_search([s], "zzz")
      assert result == []
    end

    test "query is trimmed before matching" do
      s = session(%{name: "alpha session"})
      result = SessionFilters.filter_agents_by_search([s], "  alpha  ")
      assert [^s] = result
    end
  end

  # ---------------------------------------------------------------------------
  # sort_agents/2
  # ---------------------------------------------------------------------------

  describe "sort_agents/2" do
    test "'name' sorts sessions alphabetically by name ascending" do
      s_z = session(%{id: 1, name: "Zebra"})
      s_a = session(%{id: 2, name: "Apple"})
      s_m = session(%{id: 3, name: "Mango"})

      result = SessionFilters.sort_agents([s_z, s_a, s_m], "name")
      assert Enum.map(result, & &1.name) == ["Apple", "Mango", "Zebra"]
    end

    test "'name' sort is case-insensitive" do
      s_upper = session(%{id: 1, name: "Beta"})
      s_lower = session(%{id: 2, name: "alpha"})

      result = SessionFilters.sort_agents([s_upper, s_lower], "name")
      assert List.first(result).name == "alpha"
    end

    test "'status' sorts by session_status_rank ascending" do
      working = session(%{id: 1, status: "working"})
      completed = session(%{id: 2, status: "completed"})
      discovered = session(%{id: 3, status: "discovered"})

      result = SessionFilters.sort_agents([working, completed, discovered], "status")
      statuses = Enum.map(result, & &1.status)
      assert statuses == ["discovered", "working", "completed"]
    end

    test "'model' sorts by model name ascending" do
      s_z = session(%{id: 1, model: "zephyr", model_name: nil})
      s_a = session(%{id: 2, model: "anthropic-model", model_name: nil})

      result = SessionFilters.sort_agents([s_z, s_a], "model")
      assert List.first(result).id == 2
    end

    test "'model' prefers model_name over model when present" do
      s1 = session(%{id: 1, model: "zzz", model_name: "Alpha Model"})
      s2 = session(%{id: 2, model: "aaa", model_name: "Beta Model"})

      result = SessionFilters.sort_agents([s2, s1], "model")
      assert List.first(result).id == 1
    end

    test "'recent' sorts by last_activity_at descending" do
      old = session(%{id: 1, last_activity_at: ago_iso(7200), started_at: ago_iso(7200)})
      new = session(%{id: 2, last_activity_at: ago_iso(60), started_at: ago_iso(60)})

      result = SessionFilters.sort_agents([old, new], "recent")
      assert List.first(result).id == 2
    end

    test "'last_message' sorts by last_activity_at descending" do
      old = session(%{id: 1, last_activity_at: ago_iso(3600), started_at: ago_iso(3600)})
      new = session(%{id: 2, last_activity_at: ago_iso(100), started_at: ago_iso(100)})

      result = SessionFilters.sort_agents([old, new], "last_message")
      assert List.first(result).id == 2
    end

    test "unknown sort falls back to last_message (last_activity_at desc)" do
      old = session(%{id: 1, last_activity_at: ago_iso(3600), started_at: ago_iso(3600)})
      new = session(%{id: 2, last_activity_at: ago_iso(30), started_at: ago_iso(30)})

      result = SessionFilters.sort_agents([old, new], "unknown_sort_key")
      assert List.first(result).id == 2
    end

    test "'created' sorts by started_at descending" do
      old = session(%{id: 1, started_at: ago_iso(7200)})
      new = session(%{id: 2, started_at: ago_iso(60)})

      result = SessionFilters.sort_agents([old, new], "created")
      assert List.first(result).id == 2
    end
  end

  # ---------------------------------------------------------------------------
  # session_status_rank/1
  # ---------------------------------------------------------------------------

  describe "session_status_rank/1" do
    test "'discovered' returns 0" do
      assert SessionFilters.session_status_rank(%{status: "discovered"}) == 0
    end

    test "'working' returns 1" do
      assert SessionFilters.session_status_rank(%{status: "working"}) == 1
    end

    test "'idle' returns 1" do
      assert SessionFilters.session_status_rank(%{status: "idle"}) == 1
    end

    test "nil status returns 1" do
      assert SessionFilters.session_status_rank(%{status: nil}) == 1
    end

    test "'completed' returns 2" do
      assert SessionFilters.session_status_rank(%{status: "completed"}) == 2
    end

    test "unknown status returns 2" do
      assert SessionFilters.session_status_rank(%{status: "some_random_status"}) == 2
    end

    test "rank order: discovered < working == idle < completed" do
      assert SessionFilters.session_status_rank(%{status: "discovered"}) <
               SessionFilters.session_status_rank(%{status: "working"})

      assert SessionFilters.session_status_rank(%{status: "working"}) ==
               SessionFilters.session_status_rank(%{status: "idle"})

      assert SessionFilters.session_status_rank(%{status: "working"}) <
               SessionFilters.session_status_rank(%{status: "completed"})
    end
  end

  # ---------------------------------------------------------------------------
  # to_string_or_empty/1
  # ---------------------------------------------------------------------------

  describe "to_string_or_empty/1" do
    test "nil returns empty string" do
      assert SessionFilters.to_string_or_empty(nil) == ""
    end

    test "binary is returned as-is" do
      assert SessionFilters.to_string_or_empty("hello") == "hello"
    end

    test "empty string is returned as-is" do
      assert SessionFilters.to_string_or_empty("") == ""
    end

    test "integer is converted to string" do
      assert SessionFilters.to_string_or_empty(42) == "42"
    end

    test "atom is converted to string" do
      assert SessionFilters.to_string_or_empty(:foo) == "foo"
    end
  end

  # ---------------------------------------------------------------------------
  # sort_datetime/1
  # ---------------------------------------------------------------------------

  describe "sort_datetime/1" do
    test "NaiveDateTime is returned as-is" do
      ndt = ~N[2024-06-01 12:00:00]
      assert SessionFilters.sort_datetime(ndt) == ndt
    end

    test "DateTime is converted to NaiveDateTime" do
      dt = ~U[2024-06-01 12:00:00Z]
      result = SessionFilters.sort_datetime(dt)
      assert %NaiveDateTime{} = result
      assert result == ~N[2024-06-01 12:00:00]
    end

    test "ISO8601 string is parsed to NaiveDateTime" do
      result = SessionFilters.sort_datetime("2024-06-01T12:00:00Z")
      assert %NaiveDateTime{} = result
      assert result == ~N[2024-06-01 12:00:00]
    end

    test "invalid string returns epoch sentinel" do
      result = SessionFilters.sort_datetime("not-a-date")
      assert result == ~N[0000-01-01 00:00:00]
    end

    test "nil returns epoch sentinel" do
      assert SessionFilters.sort_datetime(nil) == ~N[0000-01-01 00:00:00]
    end

    test "integer returns epoch sentinel" do
      assert SessionFilters.sort_datetime(12_345) == ~N[0000-01-01 00:00:00]
    end
  end
end
