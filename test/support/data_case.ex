defmodule EyeInTheSky.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use EyeInTheSky.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias EyeInTheSky.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import EyeInTheSky.DataCase
    end
  end

  setup tags do
    EyeInTheSky.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.

  Also provisions a test user so a default workspace exists for any test that
  calls `Projects.create_project` without explicitly passing `workspace_id`.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(EyeInTheSky.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    # Ensure at least one workspace exists within this test's transaction.
    # Projects.create_project falls back to the first available workspace when
    # workspace_id is not supplied, so this prevents null constraint violations
    # in tests that were written before workspace_id was required.
    EyeInTheSky.Accounts.get_or_create_user("__test_seed_#{System.unique_integer([:positive])}__")
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
