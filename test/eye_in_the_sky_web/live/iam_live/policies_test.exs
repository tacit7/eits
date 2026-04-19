defmodule EyeInTheSkyWeb.IAMLive.PoliciesTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EyeInTheSky.IAM

  setup do
    # Start from a clean slate so filter/index assertions are deterministic.
    # Another option is to scope by unique names; deleting is cheaper.
    EyeInTheSky.Repo.delete_all(EyeInTheSky.IAM.Policy)
    :ok
  end

  defp user_policy!(attrs) do
    {:ok, p} =
      IAM.create_policy(
        Map.merge(
          %{
            name: "user_#{System.unique_integer([:positive])}",
            effect: "allow",
            agent_type: "root",
            action: "Bash",
            priority: 10,
            enabled: true
          },
          attrs
        )
      )

    p
  end

  defp system_policy!(attrs) do
    {:ok, p} =
      IAM.create_policy(
        Map.merge(
          %{
            system_key: "builtin_#{System.unique_integer([:positive])}",
            name: "System policy",
            effect: "deny",
            agent_type: "*",
            action: "Bash",
            priority: 1000,
            enabled: true,
            editable_fields: ["enabled", "priority", "message"]
          },
          attrs
        )
      )

    p
  end

  describe "mount" do
    test "renders the index with the New policy button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/policies")
      assert has_element?(view, "h1", "IAM Policies")
      assert has_element?(view, "a", "New policy")
    end

    test "lists existing policies", %{conn: conn} do
      _p1 = user_policy!(%{name: "alpha"})
      _p2 = system_policy!(%{name: "beta-system"})

      {:ok, _view, html} = live(conn, ~p"/iam/policies")
      assert html =~ "alpha"
      assert html =~ "beta-system"
      assert html =~ "system"
    end

    test "shows empty-state when no policies exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/iam/policies")
      assert html =~ "No policies match the current filters."
    end
  end

  describe "filter" do
    test "narrows the list by effect", %{conn: conn} do
      user_policy!(%{name: "allow-one", effect: "allow"})
      user_policy!(%{name: "deny-one", effect: "deny"})

      {:ok, view, _html} = live(conn, ~p"/iam/policies")

      html =
        view
        |> form("#iam-policies-filter", %{"filters" => %{"effect" => "deny"}})
        |> render_change()

      assert html =~ "deny-one"
      refute html =~ "allow-one"
    end
  end

  describe "toggle" do
    test "flips the enabled flag", %{conn: conn} do
      p = user_policy!(%{name: "toggle-me", enabled: true})

      {:ok, view, _html} = live(conn, ~p"/iam/policies")

      view
      |> element("button[phx-click='toggle'][phx-value-id='#{p.id}']")
      |> render_click()

      {:ok, reloaded} = IAM.get_policy(p.id)
      refute reloaded.enabled
    end
  end

  describe "delete" do
    test "deletes a user policy", %{conn: conn} do
      p = user_policy!(%{name: "deletable"})

      {:ok, view, _html} = live(conn, ~p"/iam/policies")

      view
      |> element("button[phx-click='delete'][phx-value-id='#{p.id}']")
      |> render_click()

      assert {:error, :not_found} = IAM.get_policy(p.id)
    end

    test "refuses to delete a system policy (no delete button rendered)", %{conn: conn} do
      p = system_policy!(%{name: "undeletable"})

      {:ok, view, html} = live(conn, ~p"/iam/policies")

      refute has_element?(view, "button[phx-click='delete'][phx-value-id='#{p.id}']")
      assert html =~ "undeletable"
    end
  end
end
