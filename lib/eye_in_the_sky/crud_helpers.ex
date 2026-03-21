defmodule EyeInTheSky.CrudHelpers do
  @moduledoc """
  Generates standard CRUD functions for context modules via `use`.

  Eliminates the Repo.get wrapper boilerplate that every context repeats.
  All generated functions are `defoverridable` so contexts can override them
  with custom logic (preloads, PubSub broadcasts, etc.).

  ## Usage

      use EyeInTheSky.CrudHelpers, schema: MyApp.Schema
      use EyeInTheSky.CrudHelpers, schema: MyApp.Schema, repo: MyApp.Repo

  ## Generated functions

  - `get(id)` — `{:ok, record}` or `{:error, :not_found}`
  - `get!(id)` — record or raises `Ecto.NoResultsError`
  - `create(attrs)` — `%Schema{} |> Schema.changeset(attrs) |> Repo.insert()`
  - `update(record, attrs)` — `record |> Schema.changeset(attrs) |> Repo.update()`
  - `delete(record)` — `Repo.delete(record)`

  If the schema has a `:uuid` field, also generates:

  - `get_by_uuid(uuid)` — `{:ok, record}` or `{:error, :not_found}`
  - `get_by_uuid!(uuid)` — record or raises `Ecto.NoResultsError`
  """

  defmacro __using__(opts) do
    schema_ast = Keyword.fetch!(opts, :schema)
    repo = Keyword.get(opts, :repo, EyeInTheSky.Repo)

    # Expand the alias to get the actual module atom at compile time
    schema = Macro.expand(schema_ast, __CALLER__)
    has_uuid = :uuid in schema.__schema__(:fields)

    quote do
      def get(id) do
        case unquote(repo).get(unquote(schema), id) do
          nil -> {:error, :not_found}
          record -> {:ok, record}
        end
      end

      def get!(id) do
        unquote(repo).get!(unquote(schema), id)
      end

      def create(attrs \\ %{}) do
        struct(unquote(schema))
        |> unquote(schema).changeset(attrs)
        |> unquote(repo).insert()
      end

      def update(record, attrs) do
        record
        |> unquote(schema).changeset(attrs)
        |> unquote(repo).update()
      end

      def delete(record) do
        unquote(repo).delete(record)
      end

      if unquote(has_uuid) do
        def get_by_uuid(uuid) do
          case unquote(repo).get_by(unquote(schema), uuid: uuid) do
            nil -> {:error, :not_found}
            record -> {:ok, record}
          end
        end

        def get_by_uuid!(uuid) do
          unquote(repo).get_by!(unquote(schema), uuid: uuid)
        end

        defoverridable get_by_uuid: 1, get_by_uuid!: 1
      end

      defoverridable get: 1, get!: 1, create: 1, update: 2, delete: 1
    end
  end
end
