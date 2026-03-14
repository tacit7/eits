defmodule EyeInTheSkyWebWeb.Api.V1.ProjectControllerTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  alias EyeInTheSkyWeb.Projects

  import EyeInTheSkyWeb.Factory

  defp create_project(overrides \\ %{}) do
    n = uniq()

    {:ok, project} =
      Projects.create_project(
        Map.merge(
          %{
            name: "Test Project #{n}",
            slug: "test-project-#{n}",
            path: "/tmp/project-#{n}",
            active: true
          },
          overrides
        )
      )

    project
  end

  # ---- GET /api/v1/projects ----

  describe "GET /api/v1/projects" do
    test "returns project list", %{conn: conn} do
      create_project()
      conn = get(conn, ~p"/api/v1/projects")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert is_list(resp["projects"])
      assert length(resp["projects"]) >= 1
    end

    test "each project has expected fields", %{conn: conn} do
      project = create_project()
      conn = get(conn, ~p"/api/v1/projects")
      resp = json_response(conn, 200)

      found = Enum.find(resp["projects"], &(&1["id"] == project.id))
      assert found != nil
      assert found["name"] == project.name
      assert found["slug"] == project.slug
      assert Map.has_key?(found, "active")
    end
  end

  # ---- GET /api/v1/projects/:id ----

  describe "GET /api/v1/projects/:id" do
    test "returns a project by id", %{conn: conn} do
      project = create_project()
      conn = get(conn, ~p"/api/v1/projects/#{project.id}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["project"]["id"] == project.id
      assert resp["project"]["name"] == project.name
      assert resp["project"]["slug"] == project.slug
    end

    test "returns 404 for unknown project", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/projects/9999999")
      assert json_response(conn, 404)["error"] == "Project not found"
    end
  end

  # ---- POST /api/v1/projects ----

  describe "POST /api/v1/projects" do
    test "creates a project with valid params", %{conn: conn} do
      n = uniq()

      conn =
        post(conn, ~p"/api/v1/projects", %{
          "name" => "New Project #{n}",
          "slug" => "new-project-#{n}",
          "path" => "/tmp/new-project-#{n}"
        })

      resp = json_response(conn, 201)

      assert resp["success"] == true
      assert resp["message"] == "Project created"
      assert is_integer(resp["project_id"])
    end

    test "project is retrievable after creation", %{conn: conn} do
      n = uniq()
      slug = "retrieve-project-#{n}"

      conn =
        post(conn, ~p"/api/v1/projects", %{
          "name" => "Retrieve Project #{n}",
          "slug" => slug
        })

      resp = json_response(conn, 201)
      project = Projects.get_project!(resp["project_id"])
      assert project.slug == slug
    end

    test "returns 422 when name is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/projects", %{"slug" => "no-name"})
      resp = json_response(conn, 422)

      assert resp["error"] == "Failed to create project"
    end
  end
end
