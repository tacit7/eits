# lib/eye_in_the_sky_web/components/file_editor_component.ex
defmodule EyeInTheSkyWeb.Components.FileEditorComponent do
  use EyeInTheSkyWeb, :html

  @doc """
  Renders a CodeMirror 6 in-browser file editor.

  The parent LiveView must:
  - Set `edit_path` in its socket assigns (server-side only; never sent to client)
  - Handle the `"file_changed"` event and write content to `socket.assigns.edit_path`

  ## Assigns
  - `file_content` (required) — base64-encoded content via `Base.encode64/1`
  - `file_lang` (required) — language: "elixir", "javascript", "shell", "markdown", "text"
  - `file_error` (optional) — if set, renders an error state instead of the editor
  """
  attr :file_content, :string, required: true
  attr :file_lang, :string, required: true
  attr :file_error, :string, default: nil

  def file_editor(assigns) do
    ~H"""
    <%= if @file_error do %>
      <div class="alert alert-error text-sm">
        <.icon name="hero-exclamation-circle" class="w-4 h-4" />
        <span>Could not load file: {@file_error}</span>
      </div>
    <% else %>
      <div
        phx-hook="CodeMirror"
        id="codemirror-editor"
        data-content={@file_content}
        data-lang={@file_lang}
        class="border border-base-300 rounded-lg overflow-hidden min-h-64"
      >
      </div>
    <% end %>
    """
  end

  @doc "Infer CodeMirror language string from file path extension."
  def infer_lang(path) when is_binary(path) do
    case Path.extname(path) do
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".js" -> "javascript"
      ".ts" -> "javascript"
      ".css" -> "css"
      ".html" -> "html"
      ".heex" -> "html"
      ".md" -> "markdown"
      ".json" -> "json"
      ".sh" -> "shell"
      ".bash" -> "shell"
      _ -> "text"
    end
  end

  def infer_lang(_), do: "text"
end
