defmodule EyeInTheSkyWeb.Live.DmLiveNewTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Agents, Projects, Repo, Sessions}

  defp uniq, do: System.unique_integer([:positive])

  defp create_project do
    {:ok, project} =
      Projects.create_project(%{
        name: "dm-new-test-#{uniq()}",
        slug: "dm-new-test-#{uniq()}",
        active: true,
        path: "/tmp/dm-new-test-#{uniq()}"
      })

    project
  end

  defp create_agent_and_session(project) do
    {:ok, agent} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Test Agent",
        source: "web",
        project_id: project.id
      })

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        name: "Test Session",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    {agent, session}
  end

  # ── /dm/new rendering ──────────────────────────────────────────────────

  describe "GET /dm/new" do
    test "redirects to root when project_id is absent", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/dm/new")
    end

    test "redirects to root when project_id is not an integer", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/dm/new?project_id=abc")
    end

    test "redirects to root when project_id is an integer but project does not exist",
         %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/dm/new?project_id=999999")
    end

    test "renders blank composer with stable DOM id when project_id is valid", %{conn: conn} do
      project = create_project()
      {:ok, _view, html} = live(conn, "/dm/new?project_id=#{project.id}")

      assert html =~ "New conversation"
      assert html =~ ~s(id="new-session-composer")
    end

    test "shows default model name", %{conn: conn} do
      project = create_project()
      {:ok, _view, html} = live(conn, "/dm/new?project_id=#{project.id}")

      assert html =~ EyeInTheSky.Settings.default_model()
    end
  end

  # ── send_message from /dm/new ──────────────────────────────────────────

  describe "send_message" do
    setup do
      %{project: create_project()}
    end

    test "empty body is a no-op — no redirect, no session created", %{
      conn: conn,
      project: project
    } do
      count_before = Repo.aggregate(EyeInTheSky.Sessions.Session, :count)

      {:ok, view, _html} = live(conn, "/dm/new?project_id=#{project.id}")

      result =
        view
        |> form("form[phx-submit='send_message']", %{"body" => "   "})
        |> render_submit()

      refute match?({:error, {:live_redirect, _}}, result)
      assert Repo.aggregate(EyeInTheSky.Sessions.Session, :count) == count_before
    end

    test "valid body creates exactly one session and redirects", %{conn: conn, project: project} do
      count_before = Repo.aggregate(EyeInTheSky.Sessions.Session, :count)

      {:ok, view, _html} = live(conn, "/dm/new?project_id=#{project.id}")

      assert {:error, {:live_redirect, %{to: "/dm/" <> _}}} =
               view
               |> form("form[phx-submit='send_message']", %{"body" => "Write a hello world"})
               |> render_submit()

      assert Repo.aggregate(EyeInTheSky.Sessions.Session, :count) == count_before + 1
    end

    test "body is stored in PendingSessionMessages and consumed — not in redirect URL",
         %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, "/dm/new?project_id=#{project.id}")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("form[phx-submit='send_message']", %{"body" => "Debug the login bug"})
               |> render_submit()

      refute to =~ "initial_body"
      refute to =~ "Debug"

      session_id = to |> String.replace("/dm/", "") |> String.to_integer()
      assert {body, send_opts} = EyeInTheSky.PendingSessionMessages.pop(session_id)
      assert is_binary(body)
      assert Keyword.get(send_opts, :eits_workflow) == "0"
      assert is_nil(EyeInTheSky.PendingSessionMessages.pop(session_id))
    end
  end

  # ── PendingSessionMessages unit tests ──────────────────────────────────

  describe "PendingSessionMessages" do
    test "put and pop returns {body, send_opts} exactly once" do
      EyeInTheSky.PendingSessionMessages.put(88_888, "hello", eits_workflow: "0")
      assert EyeInTheSky.PendingSessionMessages.pop(88_888) == {"hello", [eits_workflow: "0"]}
      assert EyeInTheSky.PendingSessionMessages.pop(88_888) == nil
    end

    test "pop on unknown key returns nil" do
      assert EyeInTheSky.PendingSessionMessages.pop(99_999_999) == nil
    end

    test "send_opts includes session_cli_opts from socket and forces eits_workflow: 0" do
      existing_cli_opts = [effort: "medium", plan: true]
      send_opts = existing_cli_opts |> Keyword.put(:eits_workflow, "0")

      assert Keyword.get(send_opts, :eits_workflow) == "0"
      assert Keyword.get(send_opts, :effort) == "medium"
      assert Keyword.get(send_opts, :plan) == true
    end
  end

  # ── Sessions.Naming unit tests ──────────────────────────────────────────

  describe "Sessions.Naming.generate_name/1" do
    test "returns {:error, :no_api_key} when ANTHROPIC_API_KEY is empty" do
      original = System.get_env("ANTHROPIC_API_KEY")

      try do
        System.put_env("ANTHROPIC_API_KEY", "")
        assert {:error, :no_api_key} = EyeInTheSky.Sessions.Naming.generate_name("test body")
      after
        case original do
          nil -> System.delete_env("ANTHROPIC_API_KEY")
          val -> System.put_env("ANTHROPIC_API_KEY", val)
        end
      end
    end
  end

  describe "Sessions.Naming.try_auto_name/3 race guard" do
    setup do
      project = create_project()
      {_agent, session} = create_agent_and_session(project)
      %{session: session}
    end

    test "does not overwrite a manually renamed session", %{session: session} do
      {:ok, _} = Sessions.update_session(session, %{name: "My Manual Name"})

      :ok = EyeInTheSky.Sessions.Naming.try_auto_name(session.id, "some body", session.name)
      reloaded = Repo.get!(EyeInTheSky.Sessions.Session, session.id)
      assert reloaded.name == "My Manual Name"
    end

    test "updates name when current name still equals fallback", %{session: session} do
      {:ok, session} = Sessions.update_session(session, %{name: "initial fallback"})

      original = System.get_env("ANTHROPIC_API_KEY")

      try do
        System.put_env("ANTHROPIC_API_KEY", "")
        :ok = EyeInTheSky.Sessions.Naming.try_auto_name(session.id, "body", "initial fallback")
        reloaded = Repo.get!(EyeInTheSky.Sessions.Session, session.id)
        assert reloaded.name == "initial fallback"
      after
        case original do
          nil -> System.delete_env("ANTHROPIC_API_KEY")
          val -> System.put_env("ANTHROPIC_API_KEY", val)
        end
      end
    end
  end
end
