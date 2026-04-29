defmodule EyeInTheSkyWeb.Api.V1.TagController do
  use EyeInTheSkyWeb, :controller

  alias EyeInTheSky.TaskTags

  @doc """
  GET /api/v1/tags - List all tags.
  Optional query param: q (name search, case-insensitive substring)
  """
  def index(conn, params) do
    tags = TaskTags.list_tags()

    tags =
      case params["q"] do
        q when is_binary(q) and q != "" ->
          q_lower = String.downcase(q)
          Enum.filter(tags, fn t -> String.contains?(String.downcase(t.name), q_lower) end)

        _ ->
          tags
      end

    json(conn, %{
      success: true,
      tags: Enum.map(tags, fn t -> %{id: t.id, name: t.name} end)
    })
  end
end
