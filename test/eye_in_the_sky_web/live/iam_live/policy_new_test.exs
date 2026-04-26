defmodule EyeInTheSkyWeb.IAMLive.PolicyNewTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import EyeInTheSky.Factory

  alias EyeInTheSky.IAM

  setup do
    EyeInTheSky.Repo.delete_all(EyeInTheSky.IAM.Policy)
    :ok
  end

  describe "mount" do
    test "renders the create form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/policies/new")
      assert has_element?(view, "h1", "New IAM Policy")
      assert has_element?(view, "button[type='submit']", "Create policy")
    end
  end

  describe "save" do
    test "creates a valid policy and redirects to index", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/policies/new")

      result =
        view
        |> form("#iam-policy-form", %{
          "policy" => %{
            "name" => "My new policy",
            "effect" => "allow",
            "agent_type" => "root",
            "action" => "Bash",
            "priority" => "50",
            "enabled" => "true"
          },
          "condition_text" => "{}"
        })
        |> render_submit()

      case result do
        {:error, {:live_redirect, %{to: "/iam/policies"}}} ->
          :ok

        {:error, {:redirect, %{to: "/iam/policies"}}} ->
          :ok

        other ->
          flunk("expected redirect to /iam/policies, got: #{inspect(other, limit: 500)}")
      end

      assert [%{name: "My new policy"}] = IAM.list_policies()
    end

    test "surfaces validation errors for missing fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/policies/new")

      html =
        view
        |> form("#iam-policy-form", %{
          "policy" => %{"name" => "", "effect" => "allow"},
          "condition_text" => "{}"
        })
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
      assert IAM.list_policies() == []
    end

    test "global scope clears both project_id and project_path", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/policies/new")

      view
      |> form("#iam-policy-form", %{
        "policy" => %{
          "name" => "Global deny",
          "effect" => "deny",
          "priority" => "10",
          "enabled" => "true"
        },
        "scope" => "global",
        "condition_text" => "{}"
      })
      |> render_submit()

      assert [p] = IAM.list_policies()
      assert p.project_id == nil
      assert p.project_path == "*"
    end

    test "project scope persists project_id and leaves project_path wildcard", %{conn: conn} do
      project = project_fixture(%{name: "scope-test"})

      {:ok, view, _html} = live(conn, ~p"/iam/policies/new")

      # Switch scope first so the conditional project_id select renders.
      view
      |> form("#iam-policy-form", %{
        "policy" => %{"name" => "x", "effect" => "deny"},
        "scope" => "project",
        "condition_text" => "{}"
      })
      |> render_change()

      view
      |> form("#iam-policy-form", %{
        "policy" => %{
          "name" => "Project deny",
          "effect" => "deny",
          "project_id" => Integer.to_string(project.id),
          "priority" => "10",
          "enabled" => "true"
        },
        "scope" => "project",
        "condition_text" => "{}"
      })
      |> render_submit()

      assert [p] = IAM.list_policies()
      assert p.project_id == project.id
      assert p.project_path == "*"
    end

    test "path scope persists project_path and leaves project_id nil", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/policies/new")

      view
      |> form("#iam-policy-form", %{
        "policy" => %{"name" => "x", "effect" => "deny"},
        "scope" => "path",
        "condition_text" => "{}"
      })
      |> render_change()

      view
      |> form("#iam-policy-form", %{
        "policy" => %{
          "name" => "Path deny",
          "effect" => "deny",
          "project_path" => "/Users/me/projects/*",
          "priority" => "10",
          "enabled" => "true"
        },
        "scope" => "path",
        "condition_text" => "{}"
      })
      |> render_submit()

      assert [p] = IAM.list_policies()
      assert p.project_id == nil
      assert p.project_path == "/Users/me/projects/*"
    end

    test "rejects invalid JSON in the condition textarea", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/policies/new")

      html =
        view
        |> form("#iam-policy-form", %{
          "policy" => %{"name" => "x", "effect" => "allow"},
          "condition_text" => "{not json"
        })
        |> render_submit()

      assert html =~ "invalid JSON"
      assert IAM.list_policies() == []
    end
  end
end
