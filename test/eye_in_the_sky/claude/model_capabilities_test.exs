defmodule EyeInTheSky.Claude.ModelCapabilitiesTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.{ContentBlock, ModelCapabilities}

  describe "modalities/1" do
    test "Claude opus supports text, image, document" do
      assert :document in ModelCapabilities.modalities("opus")
      assert :image in ModelCapabilities.modalities("opus")
      assert :text in ModelCapabilities.modalities("opus")
    end

    test "Claude sonnet supports text, image, document" do
      assert :document in ModelCapabilities.modalities("sonnet")
    end

    test "Claude haiku supports text, image but not document" do
      mods = ModelCapabilities.modalities("haiku")
      assert :text in mods
      assert :image in mods
      refute :document in mods
    end

    test "OpenAI gpt-5.3-codex supports text, image" do
      mods = ModelCapabilities.modalities("gpt-5.3-codex")
      assert :text in mods
      assert :image in mods
      refute :document in mods
    end

    test "nil model defaults to text, image" do
      assert ModelCapabilities.modalities(nil) == [:text, :image]
    end

    test "unknown model defaults to text, image" do
      mods = ModelCapabilities.modalities("future-model-9000")
      assert :text in mods
      assert :image in mods
    end
  end

  describe "supports?/2" do
    test "opus supports document" do
      assert ModelCapabilities.supports?("opus", :document)
    end

    test "haiku does not support document" do
      refute ModelCapabilities.supports?("haiku", :document)
    end
  end

  describe "filter_blocks/2" do
    test "keeps all blocks for a fully capable model" do
      blocks = [
        ContentBlock.new_text("hello"),
        ContentBlock.new_image("abc", "image/png"),
        ContentBlock.new_document("application/pdf", "JVBERi0...")
      ]

      filtered = ModelCapabilities.filter_blocks(blocks, "opus")
      assert length(filtered) == 3
    end

    test "silently strips document blocks for haiku" do
      blocks = [
        ContentBlock.new_text("hello"),
        ContentBlock.new_image("abc", "image/png"),
        ContentBlock.new_document("application/pdf", "JVBERi0...")
      ]

      filtered = ModelCapabilities.filter_blocks(blocks, "haiku")
      assert length(filtered) == 2
      refute Enum.any?(filtered, &ContentBlock.document?/1)
    end

    test "keeps text blocks for any model" do
      blocks = [ContentBlock.new_text("hello")]
      assert ModelCapabilities.filter_blocks(blocks, "anything") == blocks
    end

    test "empty blocks returns empty" do
      assert ModelCapabilities.filter_blocks([], "opus") == []
    end
  end
end
