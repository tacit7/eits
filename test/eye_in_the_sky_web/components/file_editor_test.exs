defmodule EyeInTheSkyWeb.Components.FileEditorTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  import EyeInTheSkyWeb.Components.FileEditorComponent

  describe "file_editor - normal rendering" do
    test "renders CodeMirror hook when no error" do
      html =
        render_component(&file_editor/1, %{
          file_content: Base.encode64("puts 'hello'"),
          file_lang: "elixir"
        })

      assert html =~ "phx-hook=\"CodeMirror\""
    end

    test "renders codemirror editor div" do
      html =
        render_component(&file_editor/1, %{
          file_content: Base.encode64("const x = 1;"),
          file_lang: "javascript"
        })

      assert html =~ "id=\"codemirror-editor\""
    end

    test "passes file_content as base64 data attribute" do
      content = "some file content"
      encoded = Base.encode64(content)

      html =
        render_component(&file_editor/1, %{
          file_content: encoded,
          file_lang: "text"
        })

      assert html =~ "data-content=\"#{encoded}\""
    end

    test "passes file_lang as data attribute" do
      html =
        render_component(&file_editor/1, %{
          file_content: Base.encode64(""),
          file_lang: "shell"
        })

      assert html =~ "data-lang=\"shell\""
    end

    test "supports all required languages" do
      languages = ["elixir", "javascript", "shell", "markdown", "text"]

      for lang <- languages do
        html =
          render_component(&file_editor/1, %{
            file_content: Base.encode64("content"),
            file_lang: lang
          })

        assert html =~ "data-lang=\"#{lang}\""
      end
    end

    test "has proper styling classes" do
      html =
        render_component(&file_editor/1, %{
          file_content: Base.encode64(""),
          file_lang: "text"
        })

      assert html =~ "border border-base-300"
      assert html =~ "rounded-lg"
      assert html =~ "overflow-hidden"
      assert html =~ "min-h-64"
    end
  end

  describe "file_editor - error state" do
    test "renders error alert when file_error is set" do
      html =
        render_component(&file_editor/1, %{
          file_content: Base.encode64(""),
          file_lang: "text",
          file_error: "File not found"
        })

      assert html =~ "alert alert-error"
    end

    test "shows error message" do
      html =
        render_component(&file_editor/1, %{
          file_content: Base.encode64(""),
          file_lang: "text",
          file_error: "Permission denied"
        })

      assert html =~ "Could not load file: Permission denied"
    end

    test "renders error icon" do
      html =
        render_component(&file_editor/1, %{
          file_content: Base.encode64(""),
          file_lang: "text",
          file_error: "File not found"
        })

      assert html =~ "hero-exclamation-circle"
    end

    test "does not render editor when error is present" do
      html =
        render_component(&file_editor/1, %{
          file_content: Base.encode64("content"),
          file_lang: "javascript",
          file_error: "Load failed"
        })

      refute html =~ "phx-hook=\"CodeMirror\""
    end

    test "renders editor when error is nil or missing" do
      html1 =
        render_component(&file_editor/1, %{
          file_content: Base.encode64("content"),
          file_lang: "javascript",
          file_error: nil
        })

      html2 =
        render_component(&file_editor/1, %{
          file_content: Base.encode64("content"),
          file_lang: "javascript"
        })

      assert html1 =~ "phx-hook=\"CodeMirror\""
      assert html2 =~ "phx-hook=\"CodeMirror\""
    end
  end

  describe "file_editor - base64 encoding" do
    test "handles empty content" do
      encoded = Base.encode64("")

      html =
        render_component(&file_editor/1, %{
          file_content: encoded,
          file_lang: "text"
        })

      assert html =~ "data-content=\"#{encoded}\""
    end

    test "handles unicode content" do
      content = "# 日本語"
      encoded = Base.encode64(content)

      html =
        render_component(&file_editor/1, %{
          file_content: encoded,
          file_lang: "markdown"
        })

      assert html =~ "data-content=\"#{encoded}\""
    end

    test "handles multiline content" do
      content = "line1\nline2\nline3"
      encoded = Base.encode64(content)

      html =
        render_component(&file_editor/1, %{
          file_content: encoded,
          file_lang: "text"
        })

      assert html =~ "data-content=\"#{encoded}\""
    end

    test "handles special characters" do
      content = "test@#$%^&*()"
      encoded = Base.encode64(content)

      html =
        render_component(&file_editor/1, %{
          file_content: encoded,
          file_lang: "text"
        })

      assert html =~ "data-content=\"#{encoded}\""
    end
  end

  describe "file_editor - hook integration" do
    test "hook is CodeMirror" do
      html =
        render_component(&file_editor/1, %{
          file_content: Base.encode64(""),
          file_lang: "text"
        })

      assert html =~ "phx-hook=\"CodeMirror\""
    end

    test "hook has correct element id" do
      html =
        render_component(&file_editor/1, %{
          file_content: Base.encode64(""),
          file_lang: "text"
        })

      assert html =~ "id=\"codemirror-editor\""
    end

    test "data attributes are set correctly" do
      content = "test code"
      encoded = Base.encode64(content)

      html =
        render_component(&file_editor/1, %{
          file_content: encoded,
          file_lang: "elixir"
        })

      assert html =~ "data-content=\"#{encoded}\""
      assert html =~ "data-lang=\"elixir\""
    end
  end

  describe "file_editor - edge cases" do
    test "handles very large content" do
      large_content = String.duplicate("x", 50_000)
      encoded = Base.encode64(large_content)

      html =
        render_component(&file_editor/1, %{
          file_content: encoded,
          file_lang: "text"
        })

      assert html =~ "phx-hook=\"CodeMirror\""
    end

    test "handles language with special characters in error" do
      html =
        render_component(&file_editor/1, %{
          file_content: Base.encode64(""),
          file_lang: "text",
          file_error: "Error: 'file.txt' not found"
        })

      # Phoenix HTML-escapes single quotes to &#39; in rendered output
      assert html =~ "Error: &#39;file.txt&#39; not found"
    end
  end
end
