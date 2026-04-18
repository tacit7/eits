defmodule EyeInTheSkyWeb.IAMLive.PolicyNewTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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
