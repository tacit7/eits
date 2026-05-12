defmodule EyeInTheSkyWeb.DmLive.ExternalActionsTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.Factory
  alias EyeInTheSky.Repo
  alias EyeInTheSkyWeb.DmLive.ExternalActions

  # Helper to build a bare socket with assigns
  defp build_socket(assigns) do
    base = %{__changed__: %{}, flash: %{}, private: %{live_temp: %{}}}

    %Phoenix.LiveView.Socket{
      assigns: Map.merge(base, assigns)
    }
  end

  # resolve_project_path/2 accesses agent.project.path — must preload before
  # putting agent in the socket.
  defp create_agent_preloaded do
    Factory.create_agent() |> Repo.preload(:project)
  end

  describe "handle_load_diff/2" do
    test "caches a diff when not already cached" do
      session = Factory.new_session()
      agent = create_agent_preloaded()
      hash = "abc123"

      socket = build_socket(%{session: session, agent: agent, diff_cache: %{}})

      {:noreply, result} = ExternalActions.handle_load_diff(hash, socket)

      # resolve_project_path returns :error (no git repo here), stored as :error in cache
      assert Map.has_key?(result.assigns.diff_cache, hash)
    end

    test "skips loading diff when already cached" do
      session = Factory.new_session()
      agent = create_agent_preloaded()
      hash = "abc123"
      cached_diff = "already cached"

      socket =
        build_socket(%{session: session, agent: agent, diff_cache: %{hash => cached_diff}})

      {:noreply, result} = ExternalActions.handle_load_diff(hash, socket)

      assert result.assigns.diff_cache[hash] == cached_diff
    end

    test "populates independent cache entries for different hashes" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      socket = build_socket(%{session: session, agent: agent, diff_cache: %{}})

      {:noreply, result1} = ExternalActions.handle_load_diff("hash1", socket)
      {:noreply, result2} = ExternalActions.handle_load_diff("hash2", result1)

      assert Map.has_key?(result2.assigns.diff_cache, "hash1")
      assert Map.has_key?(result2.assigns.diff_cache, "hash2")
    end

    test "does not re-fetch already-cached hash" do
      session = Factory.new_session()
      agent = create_agent_preloaded()
      sentinel = "sentinel_value"

      socket = build_socket(%{session: session, agent: agent, diff_cache: %{"hash1" => sentinel}})

      {:noreply, result} = ExternalActions.handle_load_diff("hash1", socket)

      # Cache should be unchanged — no re-fetch
      assert result.assigns.diff_cache["hash1"] == sentinel
    end
  end

  describe "handle_load_cumulative_diff/1" do
    test "skips loading when already loaded" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          cumulative_diff: "already loaded",
          commits: []
        })

      {:noreply, result} = ExternalActions.handle_load_cumulative_diff(socket)

      assert result.assigns.cumulative_diff == "already loaded"
    end

    test "returns :error when commits list is empty" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          cumulative_diff: nil,
          commits: []
        })

      {:noreply, result} = ExternalActions.handle_load_cumulative_diff(socket)

      assert result.assigns.cumulative_diff == :error
    end

    test "attempts git diff when commits are present" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      fake_commits = [
        %{commit_hash: "abc123"},
        %{commit_hash: "def456"}
      ]

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          cumulative_diff: nil,
          commits: fake_commits
        })

      {:noreply, result} = ExternalActions.handle_load_cumulative_diff(socket)

      # project path will not resolve for test agent — result is :error
      assert result.assigns.cumulative_diff != nil
    end
  end

  describe "handle_open_iterm/1" do
    test "returns error flash for empty session_uuid (not a valid UUID)" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      socket =
        build_socket(%{
          session_uuid: "",
          session: %{session | provider: "claude"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      assert result.assigns.flash["error"] =~ "Invalid"
    end

    test "returns error flash when session_uuid is not a valid UUID" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      socket =
        build_socket(%{
          session_uuid: "invalid-uuid",
          session: %{session | provider: "claude"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      assert result.assigns.flash["error"] == "Invalid session UUID"
    end

    test "returns error flash for codex provider with whitespace thread id" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      socket =
        build_socket(%{
          session_uuid: "invalid thread id",
          session: %{session | provider: "codex"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      assert result.assigns.flash["error"] == "Invalid Codex thread ID"
    end

    test "returns error flash for unsupported provider" do
      session = Factory.new_session()
      agent = create_agent_preloaded()
      valid_uuid = "550e8400-e29b-41d4-a716-446655440000"

      socket =
        build_socket(%{
          session_uuid: valid_uuid,
          session: %{session | provider: "unknown"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      assert result.assigns.flash["error"] == "Unsupported provider: unknown"
    end

    @tag :host_dependent
    test "passes validation for valid codex thread id" do
      session = Factory.new_session()
      agent = create_agent_preloaded()
      thread_id = "thread-123"

      socket =
        build_socket(%{
          session_uuid: thread_id,
          session: %{session | provider: "codex"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      assert result.assigns.flash["error"] == nil
    end

    @tag :host_dependent
    test "passes validation for valid claude UUID" do
      session = Factory.new_session()
      agent = create_agent_preloaded()
      valid_uuid = "550e8400-e29b-41d4-a716-446655440000"

      socket =
        build_socket(%{
          session_uuid: valid_uuid,
          session: %{session | provider: "claude"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      assert result.assigns.flash["error"] == nil
    end

    @tag :host_dependent
    test "passes validation for valid gemini UUID" do
      session = Factory.new_session()
      agent = create_agent_preloaded()
      valid_uuid = "550e8400-e29b-41d4-a716-446655440000"

      socket =
        build_socket(%{
          session_uuid: valid_uuid,
          session: %{session | provider: "gemini"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      assert result.assigns.flash["error"] == nil
    end

    test "defaults provider to claude when session.provider is nil" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      socket =
        build_socket(%{
          session_uuid: "not-a-uuid",
          session: %{session | provider: nil},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      # nil provider falls back to "claude" — invalid UUID is rejected
      assert result.assigns.flash["error"] == "Invalid session UUID"
    end
  end

  describe "validate_resume_id/2 (exercised via handle_open_iterm)" do
    @tag :host_dependent
    test "accepts valid UUID for claude" do
      session = Factory.new_session()
      agent = create_agent_preloaded()
      valid_uuid = "550e8400-e29b-41d4-a716-446655440000"

      socket =
        build_socket(%{
          session_uuid: valid_uuid,
          session: %{session | provider: "claude"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      assert result.assigns.flash["error"] == nil
    end

    test "rejects non-UUID string for claude" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      socket =
        build_socket(%{
          session_uuid: "not-a-uuid",
          session: %{session | provider: "claude"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      assert result.assigns.flash["error"] == "Invalid session UUID"
    end

    @tag :host_dependent
    test "accepts non-whitespace string for codex" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      socket =
        build_socket(%{
          session_uuid: "valid-thread-123",
          session: %{session | provider: "codex"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      assert result.assigns.flash["error"] == nil
    end

    test "rejects whitespace-containing string for codex" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      socket =
        build_socket(%{
          session_uuid: "thread with spaces",
          session: %{session | provider: "codex"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      assert result.assigns.flash["error"] == "Invalid Codex thread ID"
    end
  end
end
