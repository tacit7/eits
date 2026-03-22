defmodule EyeInTheSky.Bookmarks.Bookmark do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "bookmarks" do
    field :uuid, Ecto.UUID
    field :bookmark_type, :string
    field :bookmark_id, :string
    field :file_path, :string
    field :line_number, :integer
    field :url, :string
    field :title, :string
    field :description, :string
    field :category, :string
    field :priority, :integer, default: 0
    field :position, :integer
    field :project_id, :integer
    field :agent_id, :integer
    field :accessed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(bookmark, attrs) do
    bookmark
    |> cast(attrs, [
      :bookmark_type,
      :bookmark_id,
      :file_path,
      :line_number,
      :url,
      :title,
      :description,
      :category,
      :priority,
      :position,
      :project_id,
      :agent_id,
      :accessed_at
    ])
    |> validate_required([:bookmark_type])
    |> validate_inclusion(:bookmark_type, ~w(file note agent session task url))
    |> validate_bookmark_fields()
  end

  defp validate_bookmark_fields(changeset) do
    type = get_field(changeset, :bookmark_type)

    case type do
      "file" ->
        validate_required(changeset, [:file_path])

      "url" ->
        validate_required(changeset, [:url])

      type when type in ~w(note agent session task) ->
        validate_required(changeset, [:bookmark_id])

      _ ->
        changeset
    end
  end
end
