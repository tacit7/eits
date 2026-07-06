# credo:disable-for-this-file Credo.Check.Warning.UnsafeToAtom
defmodule EyeInTheSky.Claude.AgentWorker.PiSerializationTest do
  @moduledoc """
  Spec invariant: only one Pi turn may be active per EITS session UUID.

  Serialization is keyed by the per-session AgentWorker GenServer, not by the
  provider ref — a second prompt submitted while a turn is running must be
  QUEUED (admit_busy), never dispatched to a second harness. Pi depends on
  this for transcript-directory safety (two live harnesses writing one
  sessionDir would fork/corrupt the transcript lineage).
  """
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias EyeInTheSky.Claude.{AgentWorker, Job}

  defp running_pi_state do
    %AgentWorker{
      status: :running,
      provider: "pi",
      queue: [],
      session_id: "pi-serial-#{System.unique_integer([:positive])}",
      sdk_ref: make_ref()
    }
  end

  test "a running pi worker queues a second prompt instead of starting a second turn" do
    state = running_pi_state()

    assert {:reply, {:ok, :queued}, new_state} =
             AgentWorker.handle_call({:submit_message, "second prompt", %{}}, self(), state)

    assert [%Job{message: "second prompt"}] = new_state.queue
    # The in-flight turn is untouched: same ref, still running.
    assert new_state.sdk_ref == state.sdk_ref
    assert new_state.status == :running
  end

  test "two prompts submitted while running both queue, in order" do
    state = running_pi_state()

    {:reply, {:ok, :queued}, state} =
      AgentWorker.handle_call({:submit_message, "prompt A", %{}}, self(), state)

    {:reply, {:ok, :queued}, state} =
      AgentWorker.handle_call({:submit_message, "prompt B", %{}}, self(), state)

    assert [%Job{message: "prompt A"}, %Job{message: "prompt B"}] = state.queue
    assert state.status == :running
  end
end
