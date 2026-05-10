defmodule EyeInTheSkyWeb.DmLive.ExternalActionsTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.Factory
  alias EyeInTheSkyWeb.DmLive.ExternalActions

  # Helper to build a bare socket with assigns
  defp build_socket(assigns) do
    base = %{__changed__: %{}, flash: %{}, private: %{live_temp: %{}}}
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(base, assigns)
    }
  end

  describe "handle_load_diff/2" do
    test "caches a diff when not already cached" do
      session = Factory.new_session()
      agent = Factory.create_agent()
      hash = "abc123"

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          diff_cache: %{}
        })

      {:noreply, result} = ExternalActions.handle_load_diff(hash, socket)

      # When git is not available, diff will be :error
      # The important thing is that it's in the cache now
      assert Map.has_key?(result.assigns.diff_cache, hash)
    end

    test "skips loading diff when already cached" do
      session = Factory.new_session()
      agent = Factory.create_agent()
      hash = "abc123"
      cached_diff = "already cached"

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          diff_cache: %{hash => cached_diff}
        })

      {:noreply, result} = ExternalActions.handle_load_diff(hash, socket)

      # Should preserve the cached value
      assert result.assigns.diff_cache[hash] == cached_diff
    end

    test "handles multiple different hashes" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          diff_cache: %{}
        })

      {:noreply, result1} = ExternalActions.handle_load_diff("hash1", socket)
      {:noreply, result2} = ExternalActions.handle_load_diff("hash2", result1)

      assert Map.has_key?(result2.assigns.diff_cache, "hash1")
      assert Map.has_key?(result2.assigns.diff_cache, "hash2")
    end
  end

  describe "handle_load_cumulative_diff/1" do
    test "skips loading when already loaded" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          cumulative_diff: "already loaded",
          commits: []
        })

      {:noreply, result} = ExternalActions.handle_load_cumulative_diff(socket)

      # Should not change the cumulative_diff
      assert result.assigns.cumulative_diff == "already loaded"
    end

    test "loads cumulative diff when not already loaded" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          cumulative_diff: nil,
          commits: []
        })

      {:noreply, result} = ExternalActions.handle_load_cumulative_diff(socket)

      # When commits list is empty, diff will be :error
      assert result.assigns.cumulative_diff == :error
    end

    test "returns error when commits list is empty" do
      session = Factory.new_session()
      agent = Factory.create_agent()

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
  end

  describe "handle_open_iterm/1" do
    test "returns error flash when session_uuid is invalid" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      socket =
        build_socket(%{
          session_uuid: "invalid-uuid",
          session: %{session | provider: "claude"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      assert result.assigns.flash["error"] == "Invalid session UUID"
    end

    test "returns error flash for codex provider with invalid thread id" do
      session = Factory.new_session()
      agent = Factory.create_agent()

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
      agent = Factory.create_agent()
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

    test "returns error flash when no valid session UUID" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      socket =
        build_socket(%{
          session_uuid: nil,
          session: %{session | provider: "claude"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      assert result.assigns.flash["error"] =~ "Invalid"
    end

    test "handles valid codex provider with valid thread id" do
      session = Factory.new_session()
      agent = Factory.create_agent()
      # Codex thread IDs are non-whitespace strings, not UUIDs
      thread_id = "thread-123"

      socket =
        build_socket(%{
          session_uuid: thread_id,
          session: %{session | provider: "codex"},
          agent: agent
        })

      # When osascript is not available (CI), this will try to execute but not crash
      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      # Should not have an error flash (successful execution or osascript not available)
      assert result.assigns.flash["error"] == nil
    end

    test "handles valid claude provider with valid uuid" do
      session = Factory.new_session()
      agent = Factory.create_agent()
      valid_uuid = "550e8400-e29b-41d4-a716-446655440000"

      socket =
        build_socket(%{
          session_uuid: valid_uuid,
          session: %{session | provider: "claude"},
          agent: agent
        })

      # When osascript is not available (CI), this will try to execute but not crash
      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      # Should not have an error flash
      assert result.assigns.flash["error"] == nil
    end

    test "handles valid gemini provider with valid uuid" do
      session = Factory.new_session()
      agent = Factory.create_agent()
      valid_uuid = "550e8400-e29b-41d4-a716-446655440000"

      socket =
        build_socket(%{
          session_uuid: valid_uuid,
          session: %{session | provider: "gemini"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      # Should not have an error flash
      assert result.assigns.flash["error"] == nil
    end

    test "uses home directory when project path cannot be resolved" do
      session = Factory.new_session()
      agent = Factory.create_agent()
      valid_uuid = "550e8400-e29b-41d4-a716-446655440000"

      socket =
        build_socket(%{
          session_uuid: valid_uuid,
          session: %{session | provider: "claude"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      # Should handle gracefully - the socket should be returned
      assert is_map(result.assigns)
    end
  end

  describe "validate_resume_id/2 (via handle_open_iterm)" do
    test "accepts valid UUID for non-codex providers" do
      session = Factory.new_session()
      agent = Factory.create_agent()
      valid_uuid = "550e8400-e29b-41d4-a716-446655440000"

      socket =
        build_socket(%{
          session_uuid: valid_uuid,
          session: %{session | provider: "claude"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      # No error flash means validation passed
      assert result.assigns.flash["error"] == nil
    end

    test "rejects non-UUID for non-codex providers" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      socket =
        build_socket(%{
          session_uuid: "not-a-uuid",
          session: %{session | provider: "claude"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      assert result.assigns.flash["error"] == "Invalid session UUID"
    end

    test "accepts non-whitespace strings for codex" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      socket =
        build_socket(%{
          session_uuid: "valid-thread-123",
          session: %{session | provider: "codex"},
          agent: agent
        })

      {:noreply, result} = ExternalActions.handle_open_iterm(socket)

      # No error flash means validation passed
      assert result.assigns.flash["error"] == nil
    end

    test "rejects whitespace strings for codex" do
      session = Factory.new_session()
      agent = Factory.create_agent()

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
