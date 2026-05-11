defmodule EyeInTheSky.Metrics.TokenIngestionTest do
  @moduledoc """
  Tests for `EyeInTheSky.Metrics.TokenIngestion`.

  These tests cover:
    * `calculate_cost/2` pricing logic across opus / sonnet / haiku tiers,
      including the type-guard fallback to "sonnet" for non-binary model
      names and rounding behavior.
    * `ingest_session/1` happy path and error branches
      (`:session_not_found`, `:jsonl_not_found`, malformed UUID).
    * `ingest_all/1` aggregate counts, skip-existing semantics, and
      `force: true` reprocessing.

  `TokenIngestion` reads JSONL files from `~/.claude/projects/<escaped>/`,
  so each test stubs `$HOME` to a per-test temp dir. Because `$HOME` is
  process-global, the case is `async: false`.
  """

  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.Factory
  alias EyeInTheSky.Metrics.TokenIngestion
  alias EyeInTheSky.Repo

  # ---------------------------------------------------------------------------
  # Setup helpers
  # ---------------------------------------------------------------------------

  setup do
    home = Path.join(System.tmp_dir!(), "tokeningestion_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join([home, ".claude", "projects"]))

    prev_home = System.get_env("HOME")
    System.put_env("HOME", home)

    on_exit(fn ->
      File.rm_rf!(home)

      if prev_home do
        System.put_env("HOME", prev_home)
      else
        System.delete_env("HOME")
      end
    end)

    {:ok, home: home}
  end

  defp usage_fixture(overrides \\ %{}) do
    Map.merge(
      %{
        input_tokens: 0,
        output_tokens: 0,
        cache_creation_input_tokens: 0,
        cache_read_input_tokens: 0,
        total_tokens: 0,
        request_count: 0,
        subagent_count: 0,
        models: %{}
      },
      overrides
    )
  end

  defp assistant_jsonl(model, input, output, cache_creation \\ 0, cache_read \\ 0) do
    Jason.encode!(%{
      "type" => "assistant",
      "requestId" => "req_#{System.unique_integer([:positive])}",
      "message" => %{
        "model" => model,
        "usage" => %{
          "input_tokens" => input,
          "output_tokens" => output,
          "cache_creation_input_tokens" => cache_creation,
          "cache_read_input_tokens" => cache_read
        }
      }
    })
  end

  defp create_jsonl_session(home, escaped_path, uuid, lines) do
    project_dir = Path.join([home, ".claude", "projects", escaped_path])
    File.mkdir_p!(project_dir)
    file_path = Path.join(project_dir, "#{uuid}.jsonl")
    File.write!(file_path, Enum.join(lines, "\n"))
    file_path
  end

  defp metrics_row(session_id) do
    %{rows: rows} =
      Repo.query!(
        "SELECT tokens_used, input_tokens, output_tokens, cache_creation_input_tokens, " <>
          "cache_read_input_tokens, estimated_cost_usd, model_name, request_count, " <>
          "subagent_count, notes FROM session_metrics WHERE session_id = $1",
        [session_id]
      )

    case rows do
      [row] -> row
      _ -> nil
    end
  end

  defp metrics_count(session_id) do
    %{rows: [[count]]} =
      Repo.query!(
        "SELECT COUNT(*) FROM session_metrics WHERE session_id = $1",
        [session_id]
      )

    count
  end

  # ---------------------------------------------------------------------------
  # calculate_cost/2
  # ---------------------------------------------------------------------------

  describe "calculate_cost/2" do
    test "applies sonnet pricing for sonnet model id (defaults: 3 / 15 / 0.30 / 3.75 per MTok)" do
      usage =
        usage_fixture(%{
          input_tokens: 1_000_000,
          output_tokens: 1_000_000,
          cache_read_input_tokens: 1_000_000,
          cache_creation_input_tokens: 1_000_000
        })

      # 3.0 + 15.0 + 0.30 + 3.75 = 22.05
      assert TokenIngestion.calculate_cost(usage, "claude-sonnet-4-5") == 22.05
    end

    test "applies opus pricing for an opus model id" do
      usage = usage_fixture(%{input_tokens: 1_000_000})
      assert TokenIngestion.calculate_cost(usage, "claude-opus-4-5") == 15.0
    end

    test "applies haiku pricing for a haiku model id" do
      usage = usage_fixture(%{output_tokens: 1_000_000})
      assert TokenIngestion.calculate_cost(usage, "claude-haiku-4-5") == 4.0
    end

    test "falls back to sonnet pricing when the model name has no recognized tier" do
      usage = usage_fixture(%{input_tokens: 1_000_000})
      assert TokenIngestion.calculate_cost(usage, "unknown") == 3.0
    end

    test "falls back to sonnet pricing when model_name is non-binary (nil)" do
      usage = usage_fixture(%{input_tokens: 1_000_000})
      assert TokenIngestion.calculate_cost(usage, nil) == 3.0
    end

    test "returns 0.0 for fully zeroed usage regardless of tier" do
      assert TokenIngestion.calculate_cost(usage_fixture(), "claude-opus-4-5") == 0.0
      assert TokenIngestion.calculate_cost(usage_fixture(), "claude-haiku-4-5") == 0.0
      assert TokenIngestion.calculate_cost(usage_fixture(), "claude-sonnet-4-5") == 0.0
    end

    test "rounds to 6 decimals" do
      # 1 input_token at $3 / MTok = 0.000003
      assert TokenIngestion.calculate_cost(usage_fixture(%{input_tokens: 1}), "claude-sonnet-4-5") ==
               0.000003
    end

    test "sums input, output, cache_read, and cache_creation contributions" do
      # opus: 15 / 75 / 3.75 / 18.75 per MTok
      usage =
        usage_fixture(%{
          input_tokens: 2_000_000,
          output_tokens: 1_000_000,
          cache_read_input_tokens: 4_000_000,
          cache_creation_input_tokens: 1_000_000
        })

      # 30 + 75 + 15 + 18.75 = 138.75
      assert TokenIngestion.calculate_cost(usage, "claude-opus-4-5") == 138.75
    end
  end

  # ---------------------------------------------------------------------------
  # ingest_session/1 — error paths
  # ---------------------------------------------------------------------------

  describe "ingest_session/1 error paths" do
    test "returns {:error, :session_not_found} for a UUID with no DB session" do
      uuid = Ecto.UUID.generate()
      assert {:error, :session_not_found} = TokenIngestion.ingest_session(uuid)
    end

    test "returns {:error, :session_not_found} for a malformed UUID" do
      assert {:error, :session_not_found} = TokenIngestion.ingest_session("not-a-uuid")
    end

    test "returns {:error, :jsonl_not_found} when DB session exists but no JSONL on disk" do
      session = Factory.new_session()
      assert {:error, :jsonl_not_found} = TokenIngestion.ingest_session(session.uuid)
    end
  end

  # ---------------------------------------------------------------------------
  # ingest_session/1 — happy path
  # ---------------------------------------------------------------------------

  describe "ingest_session/1 happy path" do
    test "ingests a single session and writes a session_metrics row", %{home: home} do
      session = Factory.new_session()

      create_jsonl_session(home, "-Users-test-project", session.uuid, [
        assistant_jsonl("claude-sonnet-4-5", 1_000_000, 500_000, 0, 200_000)
      ])

      assert :ok = TokenIngestion.ingest_session(session.uuid)

      [tokens_used, input, output, cache_creation, cache_read, _cost, model, requests,
       subagents, notes] = metrics_row(session.id)

      assert tokens_used == 1_700_000
      assert input == 1_000_000
      assert output == 500_000
      assert cache_creation == 0
      assert cache_read == 200_000
      assert model == "claude-sonnet-4-5"
      assert requests == 1
      assert subagents == 0

      assert {:ok, %{"models" => %{"claude-sonnet-4-5" => 1}}} = Jason.decode(notes)
    end

    test "computes a positive cost for non-zero usage and stores it", %{home: home} do
      session = Factory.new_session()

      create_jsonl_session(home, "-Users-test-project", session.uuid, [
        assistant_jsonl("claude-sonnet-4-5", 1_000_000, 0)
      ])

      assert :ok = TokenIngestion.ingest_session(session.uuid)
      [_, _, _, _, _, cost, _, _, _, _] = metrics_row(session.id)

      cost_float =
        case cost do
          %Decimal{} = d -> Decimal.to_float(d)
          f when is_float(f) -> f
          n when is_integer(n) -> n / 1
        end

      # 1M sonnet input @ $3/MTok = $3.00
      assert_in_delta cost_float, 3.0, 0.0001
    end

    test "upserts on conflict — re-ingesting overwrites the prior row", %{home: home} do
      session = Factory.new_session()
      escaped = "-Users-test-project"

      file =
        create_jsonl_session(home, escaped, session.uuid, [
          assistant_jsonl("claude-sonnet-4-5", 100, 0)
        ])

      assert :ok = TokenIngestion.ingest_session(session.uuid)
      [tokens_v1 | _] = metrics_row(session.id)
      assert tokens_v1 == 100

      File.write!(file, assistant_jsonl("claude-sonnet-4-5", 1_000, 2_000))
      assert :ok = TokenIngestion.ingest_session(session.uuid)

      [tokens_v2, input_v2, output_v2 | _] = metrics_row(session.id)
      assert tokens_v2 == 3_000
      assert input_v2 == 1_000
      assert output_v2 == 2_000
      assert metrics_count(session.id) == 1
    end

    test "primary_model is the most-frequent model across requests", %{home: home} do
      session = Factory.new_session()

      create_jsonl_session(home, "-Users-test-project", session.uuid, [
        assistant_jsonl("claude-haiku-4-5", 100, 100),
        assistant_jsonl("claude-haiku-4-5", 100, 100),
        assistant_jsonl("claude-sonnet-4-5", 100, 100)
      ])

      assert :ok = TokenIngestion.ingest_session(session.uuid)
      [_, _, _, _, _, _, model | _] = metrics_row(session.id)
      assert model == "claude-haiku-4-5"
    end

    test "uses 'unknown' model when assistant entries have no model field", %{home: home} do
      session = Factory.new_session()

      entry =
        Jason.encode!(%{
          "type" => "assistant",
          "requestId" => "req-1",
          "message" => %{"usage" => %{"input_tokens" => 10, "output_tokens" => 5}}
        })

      create_jsonl_session(home, "-Users-foo-bar", session.uuid, [entry])

      assert :ok = TokenIngestion.ingest_session(session.uuid)
      [_, _, _, _, _, _, model | _] = metrics_row(session.id)
      assert model == "unknown"
    end

    test "skips malformed JSONL lines and processes valid entries in the same file", %{home: home} do
      session = Factory.new_session()

      lines = [
        "not valid json at all",
        "{broken: json",
        assistant_jsonl("claude-sonnet-4-5", 300, 200),
        "another bad line }}}",
        assistant_jsonl("claude-haiku-4-5", 100, 50)
      ]

      create_jsonl_session(home, "-Users-mixed", session.uuid, lines)

      assert :ok = TokenIngestion.ingest_session(session.uuid)

      [tokens_used, input, output | _] = metrics_row(session.id)
      # Only the 2 valid assistant entries contribute to totals.
      assert tokens_used == 650
      assert input == 400
      assert output == 250
    end

    test "returns :ok with zero tokens when JSONL contains only malformed lines", %{home: home} do
      session = Factory.new_session()

      lines = [
        "definitely not json",
        "{broken",
        "also bad }"
      ]

      create_jsonl_session(home, "-Users-allbad", session.uuid, lines)

      assert :ok = TokenIngestion.ingest_session(session.uuid)

      [tokens_used, _, _, _, _, _, _, requests | _] = metrics_row(session.id)
      assert tokens_used == 0
      assert requests == 0
    end

    test "ingests successfully when session has no linked agent (agent_id is nil)", %{home: home} do
      # Create a session bypassing the changeset so agent_id stays NULL.
      # This mirrors what happens when an agent is deleted (on_delete: :nilify_all).
      uuid = Ecto.UUID.generate()
      {:ok, uuid_bin} = Ecto.UUID.dump(uuid)

      Repo.query!(
        "INSERT INTO sessions (uuid, name, status, started_at) VALUES ($1, $2, $3, $4)",
        [uuid_bin, "agentless-#{uuid}", "working", DateTime.utc_now()]
      )

      %{rows: [[session_id]]} =
        Repo.query!("SELECT id FROM sessions WHERE uuid = $1", [uuid_bin])

      create_jsonl_session(home, "-Users-agentless", uuid, [
        assistant_jsonl("claude-sonnet-4-5", 500, 250)
      ])

      assert :ok = TokenIngestion.ingest_session(uuid)

      %{rows: [[agent_id_in_metrics]]} =
        Repo.query!("SELECT agent_id FROM session_metrics WHERE session_id = $1", [session_id])

      assert agent_id_in_metrics == nil
      [tokens_used | _] = metrics_row(session_id)
      assert tokens_used == 750
    end
  end

  # ---------------------------------------------------------------------------
  # ingest_all/1
  # ---------------------------------------------------------------------------

  describe "ingest_all/1" do
    test "empty $HOME returns zero counts" do
      assert %{ingested: 0, skipped: 0, errors: 0} = TokenIngestion.ingest_all()
    end

    test "skips JSONL sessions with no matching DB session", %{home: home} do
      orphan_uuid = Ecto.UUID.generate()

      create_jsonl_session(home, "-Users-orphan", orphan_uuid, [
        assistant_jsonl("claude-sonnet-4-5", 100, 100)
      ])

      assert %{ingested: 0, skipped: 1, errors: 0} = TokenIngestion.ingest_all()
    end

    test "ingests new sessions then skips them on a second pass", %{home: home} do
      session_a = Factory.new_session()
      session_b = Factory.new_session()

      create_jsonl_session(home, "-Users-a", session_a.uuid, [
        assistant_jsonl("claude-sonnet-4-5", 100, 100)
      ])

      create_jsonl_session(home, "-Users-b", session_b.uuid, [
        assistant_jsonl("claude-sonnet-4-5", 200, 200)
      ])

      assert %{ingested: 2, skipped: 0, errors: 0} = TokenIngestion.ingest_all()
      assert %{ingested: 0, skipped: 2, errors: 0} = TokenIngestion.ingest_all()
    end

    test "force: true re-processes sessions that already have metrics", %{home: home} do
      session = Factory.new_session()

      create_jsonl_session(home, "-Users-x", session.uuid, [
        assistant_jsonl("claude-sonnet-4-5", 100, 100)
      ])

      assert %{ingested: 1} = TokenIngestion.ingest_all()
      assert %{ingested: 1, skipped: 0, errors: 0} = TokenIngestion.ingest_all(force: true)
    end

    test "mixed batch — matched sessions ingest, orphans skip", %{home: home} do
      session_a = Factory.new_session()
      session_b = Factory.new_session()
      orphan_uuid = Ecto.UUID.generate()

      create_jsonl_session(home, "-Users-a", session_a.uuid, [
        assistant_jsonl("claude-sonnet-4-5", 100, 100)
      ])

      create_jsonl_session(home, "-Users-b", session_b.uuid, [
        assistant_jsonl("claude-sonnet-4-5", 100, 100)
      ])

      create_jsonl_session(home, "-Users-orphan", orphan_uuid, [
        assistant_jsonl("claude-sonnet-4-5", 100, 100)
      ])

      assert %{ingested: 2, skipped: 1, errors: 0} = TokenIngestion.ingest_all()
    end
  end
end
