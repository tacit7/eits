defmodule EyeInTheSky.Claude.AgentWorker.RetryPolicyTest do
  # DataCase needed: the max-retries path calls AgentWorkerEvents which hits the DB.
  use EyeInTheSky.DataCase, async: true

  @moduletag :capture_log

  alias EyeInTheSky.Claude.AgentWorker.RetryPolicy
  alias EyeInTheSky.Claude.Job

  # session_id must be an integer (sessions table PK). Use a large non-existent ID
  # so Sessions.get_session returns {:error, :not_found} gracefully instead of raising.
  defp base_state do
    %{
      session_id: 999_999_999,
      provider_conversation_id: nil,
      retry_timer_ref: nil,
      retry_attempt: 0,
      status: :idle,
      queue: []
    }
  end

  describe "max_retries/0" do
    test "returns a positive integer" do
      assert RetryPolicy.max_retries() > 0
    end
  end

  describe "schedule_retry_start/1 — timer already set" do
    test "returns state unchanged when retry_timer_ref is already set" do
      ref = Process.send_after(self(), :dummy, 60_000)
      state = %{base_state() | retry_timer_ref: ref, retry_attempt: 1}

      result = RetryPolicy.schedule_retry_start(state)

      assert result == state

      # Clean up the timer we created
      Process.cancel_timer(ref)
    end
  end

  describe "schedule_retry_start/1 — attempt < max_retries" do
    test "sets status to :retry_wait" do
      state = base_state()
      result = RetryPolicy.schedule_retry_start(state)
      assert result.status == :retry_wait
    end

    test "increments retry_attempt" do
      state = base_state()
      result = RetryPolicy.schedule_retry_start(state)
      assert result.retry_attempt == 1
    end

    test "sets a non-nil timer_ref" do
      state = base_state()
      result = RetryPolicy.schedule_retry_start(state)
      assert result.retry_timer_ref != nil
      assert is_reference(result.retry_timer_ref)

      # Clean up
      Process.cancel_timer(result.retry_timer_ref)
    end

    test "increments attempt correctly from non-zero" do
      state = %{base_state() | retry_attempt: 2}
      result = RetryPolicy.schedule_retry_start(state)
      assert result.retry_attempt == 3

      Process.cancel_timer(result.retry_timer_ref)
    end
  end

  describe "schedule_retry_start/1 — attempt >= max_retries" do
    test "sets status to :failed" do
      state = %{base_state() | retry_attempt: RetryPolicy.max_retries()}
      result = RetryPolicy.schedule_retry_start(state)
      assert result.status == :failed
    end

    test "clears the queue" do
      jobs = [%Job{message: "a", context: %{}}, %Job{message: "b", context: %{}}]
      state = %{base_state() | retry_attempt: RetryPolicy.max_retries(), queue: jobs}
      result = RetryPolicy.schedule_retry_start(state)
      assert result.queue == []
    end

    test "resets retry_attempt to 0" do
      state = %{base_state() | retry_attempt: RetryPolicy.max_retries()}
      result = RetryPolicy.schedule_retry_start(state)
      assert result.retry_attempt == 0
    end

    test "does not set a timer_ref" do
      state = %{base_state() | retry_attempt: RetryPolicy.max_retries()}
      result = RetryPolicy.schedule_retry_start(state)
      assert result.retry_timer_ref == nil
    end
  end

  describe "clear_retry_timer/1 — no timer set" do
    test "resets retry_attempt to 0 when timer_ref is nil" do
      state = %{base_state() | retry_attempt: 3}
      result = RetryPolicy.clear_retry_timer(state)
      assert result.retry_attempt == 0
    end

    test "leaves timer_ref as nil" do
      state = base_state()
      result = RetryPolicy.clear_retry_timer(state)
      assert result.retry_timer_ref == nil
    end
  end

  describe "clear_retry_timer/1 — timer is set" do
    test "cancels the timer" do
      ref = Process.send_after(self(), :should_be_cancelled, 60_000)
      state = %{base_state() | retry_timer_ref: ref, retry_attempt: 2}

      RetryPolicy.clear_retry_timer(state)

      # Timer should be cancelled — cancel_timer returns false if already fired/cancelled
      assert Process.cancel_timer(ref) == false
    end

    test "clears retry_timer_ref to nil" do
      ref = Process.send_after(self(), :dummy, 60_000)
      state = %{base_state() | retry_timer_ref: ref, retry_attempt: 2}

      result = RetryPolicy.clear_retry_timer(state)

      assert result.retry_timer_ref == nil
    end

    test "resets retry_attempt to 0" do
      ref = Process.send_after(self(), :dummy, 60_000)
      state = %{base_state() | retry_timer_ref: ref, retry_attempt: 4}

      result = RetryPolicy.clear_retry_timer(state)

      assert result.retry_attempt == 0
    end
  end
end
