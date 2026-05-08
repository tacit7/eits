# test/eye_in_the_sky_web/components/file_editor_component_test.exs
defmodule EyeInTheSkyWeb.Components.FileEditorComponentTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Helpers.FileHelpers

  describe "FileHelpers.cm_language/1" do
    test "elixir for .ex" do
      assert FileHelpers.cm_language("/foo/bar.ex") == "elixir"
    end

    test "elixir for .exs" do
      assert FileHelpers.cm_language("/foo/bar.exs") == "elixir"
    end

    test "shell for .sh" do
      assert FileHelpers.cm_language("/foo/bar.sh") == "shell"
    end

    test "text for unknown extension" do
      assert FileHelpers.cm_language("/foo/bar.toml") == "text"
    end

    test "text for nil" do
      assert FileHelpers.cm_language(nil) == "text"
    end
  end
end
