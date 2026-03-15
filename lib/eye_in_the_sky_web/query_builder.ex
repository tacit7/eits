defmodule EyeInTheSkyWeb.QueryBuilder do
  @moduledoc """
  Composable query builder for eliminating duplicated list/filter patterns across contexts.

  Provides generic helpers that conditionally apply Ecto query clauses based on an opts keyword list.
  Context modules call these directly or via `apply_filters/2` to build reusable base queries
  shared between list and count functions.

  ## Usage

      defp base_query(opts) do
        MySchema
        |> QueryBuilder.maybe_where(opts, :state_id)
        |> QueryBuilder.maybe_where(opts, :project_id)
      end

      def list_things(opts \\\\ []) do
        base_query(opts)
        |> QueryBuilder.maybe_order(opts, desc: :created_at)
        |> QueryBuilder.maybe_limit(opts)
        |> QueryBuilder.maybe_offset(opts)
        |> Repo.all()
      end

      def count_things(opts \\\\ []) do
        base_query(opts)
        |> Repo.aggregate(:count, :id)
      end
  """

  import Ecto.Query, warn: false

  # Fields that maybe_where/3 is permitted to filter on via dynamic field(x, ^field) access.
  # Extend this list when adding new filter fields; passing an unlisted atom raises at runtime.
  @allowed_where_fields [:project_id, :status, :state_id, :agent_id, :session_id]

  @doc """
  Applies common filters from opts: project_id, status, state_id, limit, offset.
  Does not apply order_by since defaults are schema-specific — call maybe_order/3 separately.
  """
  def apply_filters(query, opts) do
    query
    |> maybe_where(opts, :project_id)
    |> maybe_where(opts, :status)
    |> maybe_where(opts, :state_id)
    |> maybe_limit(opts)
    |> maybe_offset(opts)
  end

  @doc """
  Conditionally adds a WHERE clause if `field` is present and non-nil in opts.

      maybe_where(query, opts, :state_id)
      # => WHERE state_id = ^value (only if opts[:state_id] is set)

  `field` must be one of `@allowed_where_fields`. Passing an unlisted atom raises
  `ArgumentError` to prevent accidental dynamic field access on arbitrary columns.
  """
  def maybe_where(query, opts, field) when field in @allowed_where_fields do
    case Keyword.get(opts, field) do
      nil -> query
      value -> where(query, [x], field(x, ^field) == ^value)
    end
  end

  def maybe_where(_query, _opts, field) do
    raise ArgumentError,
      "maybe_where/3 does not allow filtering on :#{field}. " <>
        "Add it to @allowed_where_fields in QueryBuilder if it is intentional."
  end

  @doc """
  Applies LIMIT if opts[:limit] is present.
  """
  def maybe_limit(query, opts) do
    case Keyword.get(opts, :limit) do
      nil -> query
      limit -> limit(query, ^limit)
    end
  end

  @doc """
  Applies OFFSET if opts[:offset] is present and greater than 0.
  """
  def maybe_offset(query, opts) do
    case Keyword.get(opts, :offset, 0) do
      n when n > 0 -> offset(query, ^n)
      _ -> query
    end
  end

  @doc """
  Applies ORDER BY from opts[:order_by] or falls back to `default`.
  Pass an empty list as default to skip ordering when opts has no :order_by.

      maybe_order(query, opts, desc: :created_at)
  """
  def maybe_order(query, opts, default) do
    order = Keyword.get(opts, :order_by, default)

    case order do
      [] -> query
      ord -> order_by(query, ^ord)
    end
  end
end
