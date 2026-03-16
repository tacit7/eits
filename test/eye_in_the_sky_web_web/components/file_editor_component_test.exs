# test/eye_in_the_sky_web_web/components/file_editor_component_test.exs
defmodule EyeInTheSkyWebWeb.Components.FileEditorComponentTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWebWeb.Components.FileEditorComponent

  describe "infer_lang/1" do
    test "elixir for .ex" do
      assert FileEditorComponent.infer_lang("/foo/bar.ex") == "elixir"
    end

    test "elixir for .exs" do
      assert FileEditorComponent.infer_lang("/foo/bar.exs") == "elixir"
    end

    test "shell for .sh" do
      assert FileEditorComponent.infer_lang("/foo/bar.sh") == "shell"
    end

    test "text for unknown extension" do
      assert FileEditorComponent.infer_lang("/foo/bar.toml") == "text"
    end

    test "text for nil" do
      assert FileEditorComponent.infer_lang(nil) == "text"
    end
  end
end
