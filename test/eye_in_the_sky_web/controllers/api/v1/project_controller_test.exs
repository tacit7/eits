defmodule EyeInTheSkyWeb.Api.V1.ProjectControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Projects
  alias EyeInTheSky.Accounts.ApiKey

  import EyeInTheSky.Factory

  defp api_conn do
    token = "test_api_key_#{System.unique_integer([:positive])}"
    {:ok, _} = ApiKey.create(token, "test")
    Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end

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
    test "returns project list" do
      create_project()
      conn = get(api_conn(), ~p"/api/v1/projects")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert is_list(resp["projects"])
      assert resp["projects"] != []
    end

    test "each project has expected fields" do
      project = create_project()
      conn = get(api_conn(), ~p"/api/v1/projects")
      resp = json_response(conn, 200)

      found = Enum.find(resp["projects"], &(&1["id"] == project.id))
      assert found != nil
      assert found["name"] == project.name
      assert found["slug"] == project.slug
      assert Map.has_key?(found, "active")
    end

    test "filters by path when ?path= is given" do
      n = uniq()
      target_path = "/tmp/target-project-#{n}"
      target = create_project(%{path: target_path})
      other = create_project(%{path: "/tmp/other-project-#{n}"})

      conn = get(api_conn(), ~p"/api/v1/projects", path: target_path)
      resp = json_response(conn, 200)

      assert resp["success"] == true
      ids = Enum.map(resp["projects"], & &1["id"])
      assert target.id in ids
      refute other.id in ids
    end

    test "returns empty list when ?path= matches nothing" do
      conn = get(api_conn(), ~p"/api/v1/projects", path: "/tmp/no-such-project-#{uniq()}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["projects"] == []
    end
  end

  # ---- GET /api/v1/projects/:id ----

  describe "GET /api/v1/projects/:id" do
    test "returns a project by id" do
      project = create_project()
      conn = get(api_conn(), ~p"/api/v1/projects/#{project.id}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["project"]["id"] == project.id
      assert resp["project"]["name"] == project.name
      assert resp["project"]["slug"] == project.slug
    end

    test "returns 404 for unknown project" do
      conn = get(api_conn(), ~p"/api/v1/projects/9999999")
      assert json_response(conn, 404)["error"] == "Project not found"
    end
  end

  # ---- POST /api/v1/projects ----

  describe "POST /api/v1/projects" do
    test "creates a project with valid params" do
      n = uniq()

      conn =
        post(api_conn(), ~p"/api/v1/projects", %{
          "name" => "New Project #{n}",
          "slug" => "new-project-#{n}",
          "path" => "/tmp/new-project-#{n}"
        })

      resp = json_response(conn, 201)

      assert resp["success"] == true
      assert resp["message"] == "Project created"
      assert is_integer(resp["project_id"])
    end

    test "project is retrievable after creation" do
      n = uniq()
      slug = "retrieve-project-#{n}"

      conn =
        post(api_conn(), ~p"/api/v1/projects", %{
          "name" => "Retrieve Project #{n}",
          "slug" => slug
        })

      resp = json_response(conn, 201)
      project = Projects.get_project!(resp["project_id"])
      assert project.slug == slug
    end

    test "returns 422 when name is missing" do
      conn = post(api_conn(), ~p"/api/v1/projects", %{"slug" => "no-name"})
      resp = json_response(conn, 422)

      assert resp["error"] == "Failed to create project"
    end
  end
end
