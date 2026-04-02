defmodule EyeInTheSky.Claude.ContentBlockTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.ContentBlock
  alias EyeInTheSky.Claude.ContentBlock.{Text, Image, Document}

  describe "constructors" do
    test "new_text/1 creates a Text block" do
      block = ContentBlock.new_text("hello")
      assert %Text{text: "hello"} = block
    end

    test "new_image/2 creates an Image block" do
      block = ContentBlock.new_image("iVBOR...", "image/png")
      assert %Image{data: "iVBOR...", mime_type: "image/png"} = block
    end

    test "new_document/2 creates a Document block with base64 source" do
      block = ContentBlock.new_document("application/pdf", "JVBERi0...")
      assert %Document{source: %{type: "base64", media_type: "application/pdf", data: "JVBERi0..."}} = block
    end
  end

  describe "type guards" do
    test "text?/1 returns true for Text blocks" do
      assert ContentBlock.text?(%Text{text: "hello"})
      refute ContentBlock.text?(%Image{data: "x", mime_type: "image/png"})
      refute ContentBlock.text?("string")
    end

    test "image?/1 returns true for Image blocks" do
      assert ContentBlock.image?(%Image{data: "x", mime_type: "image/png"})
      refute ContentBlock.image?(%Text{text: "hello"})
      refute ContentBlock.image?(nil)
    end

    test "document?/1 returns true for Document blocks" do
      assert ContentBlock.document?(%Document{source: %{type: "base64", media_type: "application/pdf", data: "x"}})
      refute ContentBlock.document?(%Text{text: "hello"})
      refute ContentBlock.document?(42)
    end
  end
end
