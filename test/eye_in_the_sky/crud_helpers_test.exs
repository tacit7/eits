defmodule EyeInTheSky.CrudHelpersTest do
  @moduledoc """
  Tests for the `EyeInTheSky.CrudHelpers` `__using__/1` macro.

  We exercise the macro by `use`-ing it inside two ad-hoc test contexts:

    * `ProjectCrud` — Project schema has NO `:uuid` field, so the macro
      should generate only `get/1`, `get!/1`, `create/1`, `update/2`,
      `delete/1` (no `get_by_uuid/{1,!}`).

    * `AgentCrud` — Agent schema HAS a `:uuid` field, so the macro should
      additionally generate `get_by_uuid/1` and `get_by_uuid!/1`.

  Tests cover happy paths, the not-found tuple/raise variants, validation
  failures via the schema's changeset, that all generated callbacks are
  `defoverridable`, and that the default `:repo` option falls through to
  `EyeInTheSky.Repo`.
  """
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Factory

  defmodule ProjectCrud do
    @moduledoc false
    use EyeInTheSky.CrudHelpers, schema: EyeInTheSky.Projects.Project
  end

  defmodule AgentCrud do
    @moduledoc false
    use EyeInTheSky.CrudHelpers, schema: EyeInTheSky.Agents.Agent
  end

  describe "use CrudHelpers — schema without :uuid (Project)" do
    test "exports get/1, get!/1, create/1, update/2, delete/1" do
      exported = ProjectCrud.__info__(:functions)

      assert {:get, 1} in exported
      assert {:get!, 1} in exported
      # create/1 with default arg also exposes create/0
      assert {:create, 1} in exported
      assert {:update, 2} in exported
      assert {:delete, 1} in exported
    end

    test "does NOT export get_by_uuid/1 or get_by_uuid!/1 when schema lacks :uuid" do
      exported = ProjectCrud.__info__(:functions)
      refute {:get_by_uuid, 1} in exported
      refute {:get_by_uuid!, 1} in exported
    end

    test "get/1 returns {:ok, record} for an existing id" do
      project = Factory.project_fixture()
      assert {:ok, fetched} = ProjectCrud.get(project.id)
      assert fetched.id == project.id
      assert fetched.name == project.name
    end

    test "get/1 returns {:error, :not_found} for a missing id" do
      assert {:error, :not_found} = ProjectCrud.get(-1)
    end

    test "get!/1 returns the record for an existing id" do
      project = Factory.project_fixture()
      fetched = ProjectCrud.get!(project.id)
      assert fetched.id == project.id
    end

    test "get!/1 raises Ecto.NoResultsError for a missing id" do
      assert_raise Ecto.NoResultsError, fn -> ProjectCrud.get!(-1) end
    end

    test "create/1 inserts with valid attrs" do
      user = Factory.user_fixture()
      workspace = EyeInTheSky.Workspaces.default_workspace_for_user!(user)
      n = Factory.uniq()

      attrs = %{
        name: "CrudHelpers test #{n}",
        path: "/tmp/crud_helpers_#{n}",
        slug: "crud-helpers-#{n}",
        workspace_id: workspace.id
      }

      assert {:ok, project} = ProjectCrud.create(attrs)
      assert project.id
      assert project.name == attrs.name

      # Round-trip via get/1
      assert {:ok, ^project} = ProjectCrud.get(project.id)
    end

    test "create/0 (default arg) returns a changeset error when required fields are missing" do
      assert {:error, %Ecto.Changeset{valid?: false} = cs} = ProjectCrud.create()
      # Project changeset validates :name and :workspace_id as required.
      errors = errors_on(cs)
      assert errors[:name] || errors[:workspace_id]
    end

    test "update/2 applies a changeset and persists" do
      project = Factory.project_fixture()
      assert {:ok, updated} = ProjectCrud.update(project, %{name: "renamed"})
      assert updated.id == project.id
      assert updated.name == "renamed"
      # Sanity: persisted to DB.
      assert {:ok, reloaded} = ProjectCrud.get(project.id)
      assert reloaded.name == "renamed"
    end

    test "update/2 returns {:error, changeset} when changeset is invalid" do
      project = Factory.project_fixture()
      # name is required → setting nil should fail validation.
      assert {:error, %Ecto.Changeset{valid?: false} = cs} =
               ProjectCrud.update(project, %{name: nil})

      assert errors_on(cs)[:name]
    end

    test "delete/1 removes the record" do
      project = Factory.project_fixture()
      assert {:ok, _} = ProjectCrud.delete(project)
      assert {:error, :not_found} = ProjectCrud.get(project.id)
    end
  end

  describe "use CrudHelpers — schema with :uuid (Agent)" do
    test "exports get_by_uuid/1 and get_by_uuid!/1 when schema has :uuid" do
      exported = AgentCrud.__info__(:functions)
      assert {:get_by_uuid, 1} in exported
      assert {:get_by_uuid!, 1} in exported
    end

    test "get_by_uuid/1 returns {:ok, record} for a known uuid" do
      agent = Factory.create_agent()
      assert {:ok, fetched} = AgentCrud.get_by_uuid(agent.uuid)
      assert fetched.id == agent.id
      assert fetched.uuid == agent.uuid
    end

    test "get_by_uuid/1 returns {:error, :not_found} for an unknown uuid" do
      assert {:error, :not_found} = AgentCrud.get_by_uuid(Ecto.UUID.generate())
    end

    test "get_by_uuid!/1 returns the record for a known uuid" do
      agent = Factory.create_agent()
      fetched = AgentCrud.get_by_uuid!(agent.uuid)
      assert fetched.id == agent.id
    end

    test "get_by_uuid!/1 raises Ecto.NoResultsError for an unknown uuid" do
      assert_raise Ecto.NoResultsError, fn ->
        AgentCrud.get_by_uuid!(Ecto.UUID.generate())
      end
    end

    test "get/1 still works on uuid-bearing schemas" do
      agent = Factory.create_agent()
      assert {:ok, fetched} = AgentCrud.get(agent.id)
      assert fetched.id == agent.id
    end
  end

  describe "defoverridable" do
    test "all generated functions are listed as overridable" do
      # Build a fresh module that uses the macro and overrides every callback;
      # if any callback is missing from `defoverridable`, the override would
      # raise a CompileError at definition time. Surviving compilation here
      # is the assertion.
      mod = Module.concat(__MODULE__, "OverrideProbe#{System.unique_integer([:positive])}")

      ast =
        quote do
          defmodule unquote(mod) do
            use EyeInTheSky.CrudHelpers, schema: EyeInTheSky.Agents.Agent

            def get(_id), do: :overridden_get
            def get!(_id), do: :overridden_get_bang
            def create(_attrs), do: :overridden_create
            def update(_record, _attrs), do: :overridden_update
            def delete(_record), do: :overridden_delete
            def get_by_uuid(_uuid), do: :overridden_get_by_uuid
            def get_by_uuid!(_uuid), do: :overridden_get_by_uuid_bang
          end
        end

      [{compiled, _bin}] = Code.compile_quoted(ast)
      assert compiled == mod
      assert mod.get(123) == :overridden_get
      assert mod.get!(123) == :overridden_get_bang
      assert mod.create(%{}) == :overridden_create
      assert mod.update(%{}, %{}) == :overridden_update
      assert mod.delete(%{}) == :overridden_delete
      assert mod.get_by_uuid("x") == :overridden_get_by_uuid
      assert mod.get_by_uuid!("x") == :overridden_get_by_uuid_bang
    end
  end

  describe "default :repo option" do
    test "falls back to EyeInTheSky.Repo when :repo is not supplied" do
      # ProjectCrud was defined without an explicit :repo, so a successful
      # round-trip against EyeInTheSky.Repo proves the default applied.
      project = Factory.project_fixture()
      assert {:ok, fetched} = ProjectCrud.get(project.id)
      assert fetched.id == project.id
    end
  end
end
