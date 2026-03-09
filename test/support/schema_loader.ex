defmodule EyeInTheSkyWeb.SchemaLoader do
  @moduledoc """
  Schema setup for tests. With PostgreSQL, schema is managed via Ecto migrations.
  This module is kept for backwards compatibility with test_helper.exs.
  """

  def load_schema! do
    :ok
  end

  def reset_database! do
    :ok
  end

  def schema_loaded? do
    case Ecto.Adapters.SQL.query(
           EyeInTheSkyWeb.Repo,
           "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename = 'sessions'",
           []
         ) do
      {:ok, %{rows: [[_name]]}} -> true
      _ -> false
    end
  end
end
