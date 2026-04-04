defmodule EyeInTheSkyWeb.Helpers.FileHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Helpers.FileHelpers

  describe "detect_file_type/1" do
    test "maps .toml to :toml" do
      assert FileHelpers.detect_file_type("config.toml") == :toml
      assert FileHelpers.detect_file_type("Cargo.toml") == :toml
    end

    test "maps known extensions correctly" do
      assert FileHelpers.detect_file_type("foo.ex") == :elixir
      assert FileHelpers.detect_file_type("foo.md") == :markdown
      assert FileHelpers.detect_file_type("foo.json") == :json
      assert FileHelpers.detect_file_type("foo.yml") == :yaml
      assert FileHelpers.detect_file_type("foo.sh") == :bash
    end

    test "falls back to :text for unknown extensions" do
      assert FileHelpers.detect_file_type("foo.xyz") == :text
      assert FileHelpers.detect_file_type("no_extension") == :text
    end
  end

  describe "language_class/1" do
    test "maps :toml to \"toml\"" do
      assert FileHelpers.language_class(:toml) == "toml"
    end

    test "maps known atoms correctly" do
      assert FileHelpers.language_class(:elixir) == "elixir"
      assert FileHelpers.language_class(:markdown) == "markdown"
      assert FileHelpers.language_class(:json) == "json"
      assert FileHelpers.language_class(:yaml) == "yaml"
      assert FileHelpers.language_class(:bash) == "bash"
    end

    test "falls back to \"plaintext\" for unknown atoms" do
      assert FileHelpers.language_class(:unknown) == "plaintext"
    end
  end

  describe "format_size/1" do
    test "formats bytes" do
      assert FileHelpers.format_size(512) == "512 B"
    end

    test "formats kilobytes" do
      assert FileHelpers.format_size(2048) == "2.0 KB"
    end

    test "formats megabytes" do
      assert FileHelpers.format_size(2 * 1024 * 1024) == "2.0 MB"
    end

    test "returns empty string for non-integer" do
      assert FileHelpers.format_size(nil) == ""
    end
  end
end
