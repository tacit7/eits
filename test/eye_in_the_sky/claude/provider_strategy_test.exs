defmodule EyeInTheSky.Claude.ProviderStrategyTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.ContentBlock
  alias EyeInTheSky.Claude.ProviderStrategy
  alias EyeInTheSky.Claude.ProviderStrategy.{Claude, Codex}

  describe "for_provider/1" do
    test "returns Codex module for codex" do
      assert ProviderStrategy.for_provider("codex") == Codex
    end

    test "returns Claude module for anything else" do
      assert ProviderStrategy.for_provider("claude") == Claude
      assert ProviderStrategy.for_provider("unknown") == Claude
    end
  end

  describe "format_content_default/1" do
    test "formats Text block" do
      block = ContentBlock.new_text("hello")

      assert ProviderStrategy.format_content_default(block) == %{
               "type" => "text",
               "text" => "hello"
             }
    end

    test "formats Image block" do
      block = ContentBlock.new_image("iVBOR...", "image/png")

      assert ProviderStrategy.format_content_default(block) == %{
               "type" => "image",
               "data" => "iVBOR...",
               "mime_type" => "image/png"
             }
    end

    test "formats Document block" do
      block = ContentBlock.new_document("application/pdf", "JVBERi0...")
      result = ProviderStrategy.format_content_default(block)
      assert result["type"] == "document"
      # Source map uses atom keys from the struct constructor
      assert result["source"][:type] == "base64"
      assert result["source"][:media_type] == "application/pdf"
    end
  end

  describe "Claude.format_content/1" do
    test "formats Text to Anthropic wire format" do
      block = ContentBlock.new_text("describe this")
      assert Claude.format_content(block) == %{"type" => "text", "text" => "describe this"}
    end

    test "formats Image to Anthropic wire format with source object" do
      block = ContentBlock.new_image("iVBOR...", "image/png")

      assert Claude.format_content(block) == %{
               "type" => "image",
               "source" => %{
                 "type" => "base64",
                 "media_type" => "image/png",
                 "data" => "iVBOR..."
               }
             }
    end

    test "formats Document to Anthropic wire format" do
      block = ContentBlock.new_document("application/pdf", "JVBERi0...")

      assert Claude.format_content(block) == %{
               "type" => "document",
               "source" => %{
                 "type" => "base64",
                 "media_type" => "application/pdf",
                 "data" => "JVBERi0..."
               }
             }
    end
  end

  describe "Claude.format_message/2" do
    test "builds content array with text first then blocks" do
      blocks = [ContentBlock.new_image("abc", "image/jpeg")]
      result = Claude.format_message("describe this", blocks)

      assert [
               %{"type" => "text", "text" => "describe this"},
               %{
                 "type" => "image",
                 "source" => %{"type" => "base64", "media_type" => "image/jpeg", "data" => "abc"}
               }
             ] = result
    end

    test "returns only text block when no content blocks" do
      result = Claude.format_message("hello", [])
      assert [%{"type" => "text", "text" => "hello"}] = result
    end
  end

  describe "Claude.eits_init_prompt/1" do
    test "includes DM placeholder instead of self-referential session_id" do
      state = %{
        eits_session_uuid: "test-uuid-123",
        session_id: 42,
        agent_id: 7,
        project_id: 1
      }

      prompt = Claude.eits_init_prompt(state)

      # Must NOT contain --to 42 (self-DM bug)
      refute prompt =~ "dm --to 42"
      # Must contain eits dm command with a placeholder (not session_id)
      assert prompt =~ "eits dm --to <session_uuid>"
    end

    test "includes eits CLI usage instructions" do
      state = %{
        eits_session_uuid: "test-uuid-456",
        session_id: 99,
        agent_id: 5,
        project_id: 2
      }

      prompt = Claude.eits_init_prompt(state)

      assert prompt =~ "eits tasks begin"
      assert prompt =~ "eits tasks annotate"
      assert prompt =~ "eits dm --to"
    end

    test "interpolates session context correctly" do
      state = %{
        eits_session_uuid: "abc-def",
        session_id: 100,
        agent_id: 50,
        project_id: 3
      }

      prompt = Claude.eits_init_prompt(state)

      assert prompt =~ "EITS_SESSION_UUID=abc-def"
      assert prompt =~ "EITS_SESSION_ID=100"
      assert prompt =~ "EITS_AGENT_ID=50"
      assert prompt =~ "EITS_PROJECT_ID=3"
    end
  end

  describe "Codex.format_content/1" do
    test "formats Text to OpenAI wire format" do
      block = ContentBlock.new_text("describe this")
      assert Codex.format_content(block) == %{"type" => "text", "text" => "describe this"}
    end

    test "formats Image to OpenAI data URI wire format" do
      block = ContentBlock.new_image("iVBOR...", "image/png")

      assert Codex.format_content(block) == %{
               "type" => "image_url",
               "image_url" => %{"url" => "data:image/png;base64,iVBOR..."}
             }
    end

    test "formats Document as unsupported text fallback" do
      block = ContentBlock.new_document("application/pdf", "JVBERi0...")
      result = Codex.format_content(block)

      assert result["type"] == "text"
      assert result["text"] =~ "not supported"
    end
  end
end
