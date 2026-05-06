defmodule EyeInTheSkyWeb.Api.V1.TagController do
  use EyeInTheSkyWeb, :controller

  alias EyeInTheSky.TaskTags

  @doc """
  GET /api/v1/tags - List all tags.
  Optional query param: q (name search, case-insensitive substring)
  """
  def index(conn, params) do
    opts =
      case params["q"] do
        q when is_binary(q) and q != "" -> [search: q]
        _ -> []
      end

    tags = TaskTags.list_tags(opts)

    json(conn, %{
      success: true,
      tags: Enum.map(tags, fn t -> %{id: t.id, name: t.name} end)
    })
  end
end
