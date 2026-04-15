defmodule EyeInTheSkyWeb.CanvasesTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSkyWeb.Canvases

  defp uniq, do: System.unique_integer([:positive])

  defp create_session do
    {:ok, agent} =
      EyeInTheSky.Agents.create_agent(%{
        name: "canvas-test-#{uniq()}",
        status: "active"
      })

    {:ok, session} =
      EyeInTheSky.Sessions.create_session(%{
        name: "canvas-session-#{uniq()}",
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "stopped"
      })

    session
  end

  test "create_canvas/1 creates a canvas with a name" do
    assert {:ok, canvas} = Canvases.create_canvas(%{name: "My Canvas"})
    assert canvas.name == "My Canvas"
  end

  test "create_canvas/1 rejects blank name" do
    assert {:error, changeset} = Canvases.create_canvas(%{name: ""})
    assert %{name: [_ | _]} = errors_on(changeset)
  end

  test "list_canvases/0 returns all canvases" do
    {:ok, c1} = Canvases.create_canvas(%{name: "A-#{uniq()}"})
    {:ok, c2} = Canvases.create_canvas(%{name: "B-#{uniq()}"})
    ids = Canvases.list_canvases() |> Enum.map(& &1.id)
    assert c1.id in ids
    assert c2.id in ids
  end

  test "add_session/2 creates a canvas_session record" do
    {:ok, canvas} = Canvases.create_canvas(%{name: "C-#{uniq()}"})
    session = create_session()
    assert {:ok, cs} = Canvases.add_session(canvas.id, session.id)
    assert cs.canvas_id == canvas.id
    assert cs.session_id == session.id
    assert cs.width == 320
  end

  test "add_session/2 is idempotent — calling twice returns ok both times" do
    {:ok, canvas} = Canvases.create_canvas(%{name: "D-#{uniq()}"})
    session = create_session()
    assert {:ok, cs1} = Canvases.add_session(canvas.id, session.id)
    assert {:ok, cs2} = Canvases.add_session(canvas.id, session.id)
    assert cs1.id != nil
    assert cs2.id != nil
  end

  test "list_canvas_sessions/1 returns sessions for a canvas" do
    {:ok, canvas} = Canvases.create_canvas(%{name: "E-#{uniq()}"})
    s1 = create_session()
    s2 = create_session()
    Canvases.add_session(canvas.id, s1.id)
    Canvases.add_session(canvas.id, s2.id)
    session_ids = Canvases.list_canvas_sessions(canvas.id) |> Enum.map(& &1.session_id)
    assert s1.id in session_ids
    assert s2.id in session_ids
  end

  test "update_window_layout/2 persists position and size" do
    {:ok, canvas} = Canvases.create_canvas(%{name: "F-#{uniq()}"})
    session = create_session()
    {:ok, cs} = Canvases.add_session(canvas.id, session.id)

    assert {:ok, updated} =
             Canvases.update_window_layout(cs.id, %{
               pos_x: 100,
               pos_y: 200,
               width: 400,
               height: 300
             })

    assert updated.pos_x == 100
    assert updated.width == 400
  end

  test "remove_session/2 deletes the canvas_session record" do
    {:ok, canvas} = Canvases.create_canvas(%{name: "G-#{uniq()}"})
    session = create_session()
    {:ok, _} = Canvases.add_session(canvas.id, session.id)
    assert :ok = Canvases.remove_session(canvas.id, session.id)
    assert Canvases.list_canvas_sessions(canvas.id) == []
  end
end
