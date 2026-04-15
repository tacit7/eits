defmodule EyeInTheSky.Agents.WebhookSanitizer do
  @moduledoc """
  Sanitizes untrusted webhook payload fields before they are embedded
  in agent instructions or shell commands.
  """

  @doc "Sanitizes a branch name: allows alphanum, _, -, ., /; collapses .. traversals."
  def sanitize_branch(b) do
    b
    |> then(&Regex.replace(~r/[^a-zA-Z0-9_\-\.\/]/, &1, "_"))
    |> String.replace("..", "_")
  end

  @doc "Sanitizes a text field: nil-safe, strips null bytes, truncates to 2000 chars."
  def sanitize_text(nil), do: ""

  def sanitize_text(s) when is_binary(s),
    do: s |> String.slice(0, 2000) |> String.replace("\0", "")

  def sanitize_text(s) when is_number(s) or is_atom(s), do: sanitize_text(to_string(s))
  def sanitize_text(_), do: ""
end
