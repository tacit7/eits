defmodule EyeInTheSkyWeb.Live.CanvasChatWindowTest do
  @moduledoc """
  Regression test for ChatWindowComponent send_message feedback.

  Before fix: handle_event("send_message") returned {:noreply, socket} unchanged —
  no messages reloaded, no visual feedback. Input stayed populated, message didn't
  appear until agent responded. User perceived send as broken.

  After fix: reloads messages immediately after send so the user's message appears
  in the window and the component re-render clears the input.
  """

  use EyeInTheSkyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Agents, Canvases, Messages, Sessions}

  defp uniq, do: System.unique_integer([:positive])

  setup %{conn: conn} do
    {:ok, agent} =
      Agents.create_agent(%{
        name: "chat-test-agent-#{uniq()}",
        status: "active"
      })

    {:ok, session} =
      Sessions.create_session(%{
        name: "chat-test-session-#{uniq()}",
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "stopped"
      })

    {:ok, canvas} = Canvases.create_canvas(%{name: "Test Canvas #{uniq()}"})
    {:ok, _cs} = Canvases.add_session(canvas.id, session.id)

    %{conn: conn, canvas: canvas, session: session}
  end

  describe "send_message in ChatWindowComponent" do
    test "user message appears immediately after send", %{
      conn: conn,
      canvas: canvas,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/canvases/#{canvas.id}")

      cs_id = canvas_session_id(canvas, session)

      view
      |> element("#chat-window-#{cs_id} form")
      |> render_submit(%{"body" => "hello from test"})

      # Message should be persisted to DB
      messages = Messages.list_recent_messages(session.id, 50)

      assert Enum.any?(messages, fn m -> m.body == "hello from test" end),
             "Expected user message to be persisted in DB after send"

      # The rendered component HTML should include the message
      html = render(view)

      assert html =~ "hello from test",
             "Expected user message to appear in rendered canvas window immediately after send"
    end

    test "empty body is ignored", %{conn: conn, canvas: canvas, session: session} do
      {:ok, view, _html} = live(conn, ~p"/canvases/#{canvas.id}")

      before_count = length(Messages.list_recent_messages(session.id, 50))

      view
      |> element("#chat-window-#{canvas_session_id(canvas, session)} form")
      |> render_submit(%{"body" => ""})

      after_count = length(Messages.list_recent_messages(session.id, 50))
      assert after_count == before_count, "Empty body should not create a message"
    end
  end

  defp canvas_session_id(canvas, session) do
    canvas.id
    |> Canvases.list_canvas_sessions()
    |> Enum.find(&(&1.session_id == session.id))
    |> Map.fetch!(:id)
  end
end
