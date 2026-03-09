defmodule EyeInTheSkyWeb.MCP.Tools.StubToolsTest do
  # These tools are either stubs, system calls, or external service calls.
  # Tests verify they return properly structured responses without crashing.
  use EyeInTheSkyWeb.DataCase, async: true

  alias EyeInTheSkyWeb.MCP.Tools.NatsListen
  alias EyeInTheSkyWeb.MCP.Tools.NatsListenRemote
  alias EyeInTheSkyWeb.MCP.Tools.Window
  alias EyeInTheSkyWeb.MCP.Tools.Speak

  @frame :test_frame

  defp decode({:reply, %Anubis.Server.Response{content: [%{"text" => json} | _]}, @frame}) do
    Jason.decode!(json, keys: :atoms)
  end

  describe "NatsListen tool (stub)" do
    test "returns empty messages list" do
      result = NatsListen.execute(%{session_id: "test-session"}, @frame) |> decode()

      assert result.success == true
      assert result.messages == []
      assert result.count == 0
    end

    test "echoes last_sequence" do
      result = NatsListen.execute(%{session_id: "test-session", last_sequence: 42}, @frame) |> decode()

      assert result.last_sequence == 42
    end

    test "defaults last_sequence to 0 when not provided" do
      result = NatsListen.execute(%{session_id: "test-session"}, @frame) |> decode()

      assert result.last_sequence == 0
    end
  end

  describe "NatsListenRemote tool (stub)" do
    test "returns empty messages list" do
      result = NatsListenRemote.execute(%{
        session_id: "test-session",
        server_url: "nats://localhost:4222"
      }, @frame) |> decode()

      assert result.success == true
      assert result.messages == []
      assert result.count == 0
    end

    test "echoes last_sequence" do
      result = NatsListenRemote.execute(%{
        session_id: "test-session",
        server_url: "nats://localhost:4222",
        last_sequence: 99
      }, @frame) |> decode()

      assert result.last_sequence == 99
    end
  end

  describe "Window tool" do
    test "returns a response without crashing" do
      # On macOS CI or dev it may succeed or fail - just verify no crash
      {:reply, response, @frame} = Window.execute(%{}, @frame)

      assert %Anubis.Server.Response{type: :tool} = response
      assert length(response.content) == 1
    end

    test "response has success field" do
      result = Window.execute(%{}, @frame) |> decode()

      assert Map.has_key?(result, :success)
    end
  end

  describe "Speak tool" do
    setup do
      # Inject a no-op `say` so tests never invoke macOS TTS
      tmp = System.tmp_dir!()
      fake_say = Path.join(tmp, "say")
      File.write!(fake_say, "#!/bin/sh\nexit 0\n")
      File.chmod!(fake_say, 0o755)
      original_path = System.get_env("PATH", "")
      System.put_env("PATH", tmp <> ":" <> original_path)
      on_exit(fn -> System.put_env("PATH", original_path) end)
      :ok
    end

    test "returns a well-formed tool response" do
      {:reply, response, @frame} = Speak.execute(%{message: "test"}, @frame)

      assert %Anubis.Server.Response{type: :tool} = response
      assert length(response.content) == 1
    end

    test "uses default voice when not specified" do
      result = Speak.execute(%{message: "hello"}, @frame) |> decode()

      assert result.success == true
      assert result.voice_used == "Ava"
    end

    test "uses specified valid voice" do
      result = Speak.execute(%{message: "hello", voice: "Lee"}, @frame) |> decode()

      assert result.success == true
      assert result.voice_used == "Lee"
    end

    test "falls back to default for invalid voice" do
      result = Speak.execute(%{message: "hello", voice: "InvalidVoice"}, @frame) |> decode()

      assert result.success == true
      assert result.voice_used == "Ava"
    end
  end
end
