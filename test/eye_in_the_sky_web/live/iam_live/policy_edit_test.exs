defmodule EyeInTheSkyWeb.IAMLive.PolicyEditTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EyeInTheSky.IAM

  setup do
    EyeInTheSky.Repo.delete_all(EyeInTheSky.IAM.Policy)
    :ok
  end

  defp user_policy!(attrs) do
    {:ok, p} =
      IAM.create_policy(
        Map.merge(
          %{name: "user policy", effect: "allow", priority: 10, enabled: true},
          attrs
        )
      )

    p
  end

  defp system_policy!(attrs \\ %{}) do
    {:ok, p} =
      IAM.create_policy(
        Map.merge(
          %{
            system_key: "builtin_#{System.unique_integer([:positive])}",
            name: "Built-in deny",
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
    test "renders the edit form for a user policy", %{conn: conn} do
      p = user_policy!(%{name: "alpha"})

      {:ok, _view, html} = live(conn, ~p"/iam/policies/#{p.id}/edit")
      assert html =~ "Edit policy"
      assert html =~ "alpha"
      refute html =~ "This is a built-in system policy."
    end

    test "shows the system-policy warning and lock banner", %{conn: conn} do
      p = system_policy!()

      {:ok, _view, html} = live(conn, ~p"/iam/policies/#{p.id}/edit")
      assert html =~ "This is a built-in system policy."
      assert html =~ "enabled, priority, message"
    end

    test "redirects to index when id is not found", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/iam/policies"}}} =
               live(conn, ~p"/iam/policies/999999/edit")
    end
  end

  describe "save — user policy" do
    test "updates whitelisted fields and redirects", %{conn: conn} do
      p = user_policy!(%{name: "original"})

      {:ok, view, _html} = live(conn, ~p"/iam/policies/#{p.id}/edit")

      assert {:ok, _, html} =
               view
               |> form("#iam-policy-form", %{
                 "policy" => %{"name" => "updated", "effect" => "allow", "priority" => "42"},
                 "condition_text" => "{}"
               })
               |> render_submit()
               |> follow_redirect(conn, ~p"/iam/policies")

      assert html =~ "updated"
      {:ok, reloaded} = IAM.get_policy(p.id)
      assert reloaded.name == "updated"
      assert reloaded.priority == 42
    end
  end

  describe "save — system policy locked fields" do
    test "locked fields render as disabled inputs in the UI", %{conn: conn} do
      p = system_policy!()

      {:ok, view, _html} = live(conn, ~p"/iam/policies/#{p.id}/edit")

      # Matcher fields are locked (not in editable_fields) → disabled
      assert has_element?(view, "input[name='policy[agent_type]'][disabled]")
      assert has_element?(view, "input[name='policy[action]'][disabled]")
      assert has_element?(view, "select[name='policy[effect]'][disabled]")

      # Whitelisted fields stay editable
      refute has_element?(view, "input[name='policy[priority]'][disabled]")
      refute has_element?(view, "input[name='policy[message]'][disabled]")
    end

    test "server-side changeset rejects locked-field edits even if the UI is bypassed", %{conn: _conn} do
      p = system_policy!()

      # Simulate a client bypassing the disabled attributes (e.g. devtools).
      # The server-side `enforce_locked_fields` in `update_changeset/2` must
      # still block the mutation. `IAM.update_policy/2` runs that changeset
      # exactly as the LiveView save handler does.
      assert {:error, %Ecto.Changeset{} = cs} =
               IAM.update_policy(p, %{"agent_type" => "code-reviewer"})

      assert {"is locked on this system policy", _} =
               Keyword.get(cs.errors, :agent_type)

      {:ok, reloaded} = IAM.get_policy(p.id)
      assert reloaded.agent_type == p.agent_type
    end

    test "editing only whitelisted fields succeeds for a system policy", %{conn: conn} do
      p = system_policy!()

      {:ok, view, _html} = live(conn, ~p"/iam/policies/#{p.id}/edit")

      # Disabled inputs (name/effect/agent_type/action) are not submitted by the
      # form helper — only whitelisted fields (enabled, priority, message) reach
      # the server, exactly like a real browser submission.
      assert {:ok, _, _html} =
               view
               |> form("#iam-policy-form", %{
                 "policy" => %{
                   "priority" => "2000",
                   "message" => "tuned by operator"
                 },
                 "condition_text" => "{}"
               })
               |> render_submit()
               |> follow_redirect(conn, ~p"/iam/policies")

      {:ok, reloaded} = IAM.get_policy(p.id)
      assert reloaded.priority == 2000
      assert reloaded.message == "tuned by operator"
    end
  end
end
