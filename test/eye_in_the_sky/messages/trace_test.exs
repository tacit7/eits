defmodule EyeInTheSky.Messages.TraceTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Messages.Trace

  describe "new/0" do
    test "returns a non-empty base64 url-safe string" do
      id = Trace.new()
      assert is_binary(id)
      assert byte_size(id) > 0
      assert id =~ ~r/^[A-Za-z0-9_-]+$/
    end

    test "returns distinct ids across 1000 calls" do
      ids = Enum.map(1..1000, fn _ -> Trace.new() end)
      assert length(Enum.uniq(ids)) == 1000
    end
  end

  describe "set_in_logger/1" do
    test "populates Logger.metadata[:message_trace_id]" do
      id = Trace.new()
      :ok = Trace.set_in_logger(id)
      assert Logger.metadata()[:message_trace_id] == id
    end
  end
end
