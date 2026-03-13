defmodule EyeInTheSkyWeb.MCP.Tools.StubToolsTest do
  # These tools are system calls or external service calls.
  # Tests verify they return properly structured responses without crashing.
  use EyeInTheSkyWeb.DataCase, async: true

  alias EyeInTheSkyWeb.MCP.Tools.Window
  alias EyeInTheSkyWeb.MCP.Tools.Speak

  @frame :test_frame

  defp decode({:reply, %Anubis.Server.Response{content: [%{"text" => json} | _]}, @frame}) do
    Jason.decode!(json, keys: :atoms)
  end

  describe "Window tool" do
    test "returns a response without crashing" do
      {:reply, response, @frame} = Window.execute(%{}, @frame)

      assert %Anubis.Server.Response{type: :tool} = response
      assert length(response.content) == 1
    end

    test "response has success field" do
      result = Window.execute(%{}, @frame) |> decode()

      assert Map.has_key?(result, :success)
    end

    test "completes within timeout" do
      # Should return (success or timed-out error) within 5s
      {elapsed, _} = :timer.tc(fn -> Window.execute(%{}, @frame) end)
      assert elapsed < 5_000_000
    end

    test "timeout returns structured error" do
      # Verify the timeout path returns a proper error struct (not a crash)
      # We can't force a timeout easily, but we verify the response is always well-formed
      result = Window.execute(%{}, @frame) |> decode()
      assert is_boolean(result.success)
      assert is_binary(result.message)
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
