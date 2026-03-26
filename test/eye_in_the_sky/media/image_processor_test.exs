defmodule EyeInTheSky.Media.ImageProcessorTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.ContentBlock
  alias EyeInTheSky.Media.ImageProcessor

  # A tiny valid 1x1 red PNG (68 bytes)
  @tiny_png_b64 "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="

  describe "process_blocks/1" do
    test "returns empty list for empty input" do
      assert ImageProcessor.process_blocks([]) == []
    end

    test "passes through text blocks unchanged" do
      blocks = [ContentBlock.new_text("hello")]
      assert ImageProcessor.process_blocks(blocks) == blocks
    end

    test "passes through small images without error" do
      block = ContentBlock.new_image(@tiny_png_b64, "image/png")
      [result] = ImageProcessor.process_blocks([block])
      assert ContentBlock.image?(result)
      # Should still be valid base64
      assert {:ok, _} = Base.decode64(result.data)
    end

    test "passes through document blocks unchanged" do
      block = ContentBlock.new_document("application/pdf", "JVBERi0...")
      assert ImageProcessor.process_blocks([block]) == [block]
    end

    test "handles mixed block types" do
      blocks = [
        ContentBlock.new_text("describe"),
        ContentBlock.new_image(@tiny_png_b64, "image/png"),
        ContentBlock.new_document("application/pdf", "JVBERi0...")
      ]

      results = ImageProcessor.process_blocks(blocks)
      assert length(results) == 3
      assert ContentBlock.text?(Enum.at(results, 0))
      assert ContentBlock.image?(Enum.at(results, 1))
      assert ContentBlock.document?(Enum.at(results, 2))
    end
  end

  describe "process_image/2" do
    test "small image passes through with valid data" do
      block = ContentBlock.new_image(@tiny_png_b64, "image/png")
      result = ImageProcessor.process_image(block)
      assert ContentBlock.image?(result)
      assert {:ok, raw} = Base.decode64(result.data)
      assert byte_size(raw) > 0
    end
  end
end
