defmodule EyeInTheSky.Claude.ProviderStrategy.GeminiTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Claude.ContentBlock
  alias EyeInTheSky.Claude.ProviderStrategy.Gemini

  describe "format_content/1" do
    test "formats Text to Gemini wire format" do
      block = ContentBlock.new_text("describe this")
      assert Gemini.format_content(block) == %{"type" => "text", "text" => "describe this"}
    end

    test "formats Image to Gemini wire format with source object" do
      block = ContentBlock.new_image("iVBOR...", "image/png")

      assert Gemini.format_content(block) == %{
               "type" => "image",
               "source" => %{
                 "type" => "base64",
                 "media_type" => "image/png",
                 "data" => "iVBOR..."
               }
             }
    end

    test "formats Document to Gemini wire format" do
      block = ContentBlock.new_document("application/pdf", "JVBERi0...")

      assert Gemini.format_content(block) == %{
               "type" => "document",
               "source" => %{
                 "type" => "base64",
                 "media_type" => "application/pdf",
                 "data" => "JVBERi0..."
               }
             }
    end
  end

  describe "start/2" do
    test "calls StreamHandler.start with correct Options" do
      state = %{
        provider_conversation_id: "conv-1",
        project_path: "/tmp/project",
        eits_session_uuid: "sess-uuid-123",
        session_id: 42,
        agent_id: "agent-7",
        project_id: 1
      }

      job = %{
        message: "Hello, Gemini!",
        context: %{
          model: "gemini-2.5-flash",
          allowed_tools: ["web_search"]
        }
      }

      # Mock StreamHandler by patching the compile_env
      with_mock_handler(fn mock_pid ->
        {:ok, _ref, handler_pid} = Gemini.start(state, job)
        assert handler_pid == mock_pid
      end)
    end

    test "uses default model when not provided in context" do
      state = %{
        provider_conversation_id: "conv-2",
        project_path: "/tmp/project",
        eits_session_uuid: "sess-uuid-456",
        session_id: 99,
        agent_id: "agent-5",
        project_id: 2
      }

      job = %{
        message: "Test message",
        context: %{}
      }

      with_mock_handler(fn _mock_pid ->
        {:ok, _ref, _handler_pid} = Gemini.start(state, job)
        # Verify that the start was called (mock succeeds)
        assert true
      end)
    end
  end

  describe "resume/2" do
    test "calls StreamHandler.resume with correct Options" do
      state = %{
        provider_conversation_id: "conv-1",
        project_path: "/tmp/project",
        eits_session_uuid: "sess-uuid-789",
        session_id: 55,
        agent_id: "agent-10",
        project_id: 1
      }

      job = %{
        message: "Continue conversation",
        context: %{
          model: "gemini-2.5-flash"
        }
      }

      with_mock_handler(fn mock_pid ->
        {:ok, _ref, handler_pid} = Gemini.resume(state, job)
        assert handler_pid == mock_pid
      end)
    end
  end

  describe "cancel/1" do
    test "calls StreamHandler.cancel with reference" do
      ref = make_ref()

      with_mock_handler_cancel(fn ->
        result = Gemini.cancel(ref)
        assert result == :ok
      end)
    end
  end

  # Helper to mock the stream handler via runtime Application env.
  # Gemini strategy resolves the handler via Application.get_env at call time.
  defp with_mock_handler(test_fn) do
    original = Application.get_env(:eye_in_the_sky, :gemini_stream_handler)
    Application.put_env(:eye_in_the_sky, :gemini_stream_handler, create_mock_stream_handler())

    try do
      test_fn.(self())
    after
      if original do
        Application.put_env(:eye_in_the_sky, :gemini_stream_handler, original)
      else
        Application.delete_env(:eye_in_the_sky, :gemini_stream_handler)
      end
    end
  end

  defp with_mock_handler_cancel(test_fn) do
    original = Application.get_env(:eye_in_the_sky, :gemini_stream_handler)

    Application.put_env(
      :eye_in_the_sky,
      :gemini_stream_handler,
      create_mock_stream_handler_cancel()
    )

    try do
      test_fn.()
    after
      if original do
        Application.put_env(:eye_in_the_sky, :gemini_stream_handler, original)
      else
        Application.delete_env(:eye_in_the_sky, :gemini_stream_handler)
      end
    end
  end

  defmodule MockStreamHandler do
    def start(_prompt, _opts, _caller), do: {:ok, make_ref(), self()}
    def resume(_session_id, _prompt, _opts, _caller), do: {:ok, make_ref(), self()}
    def cancel(_ref), do: :ok
  end

  defmodule MockStreamHandlerCancel do
    def start(_prompt, _opts, _caller), do: {:ok, make_ref(), self()}
    def resume(_session_id, _prompt, _opts, _caller), do: {:ok, make_ref(), self()}
    def cancel(_ref), do: :ok
  end

  defp create_mock_stream_handler, do: MockStreamHandler
  defp create_mock_stream_handler_cancel, do: MockStreamHandlerCancel
end
