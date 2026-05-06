defmodule EyeInTheSky.CanvasesTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Canvases
  alias EyeInTheSky.Canvases.CanvasSession

  # Mirrors the sentinel check in CanvasLive.activate_canvas/2.
  # A CanvasSession that still holds all four schema defaults has never been
  # explicitly positioned — auto-offset it. Any session that differs in at least
  # one field has been placed intentionally (including snapped windows that land
  # at pos_x=0, pos_y=0 but carry non-default dimensions).
  defp apply_sentinel_offset(sessions) do
    sessions
    |> Enum.with_index()
    |> Enum.map(fn {cs, i} ->
      if cs.pos_x == 0 and cs.pos_y == 0 and cs.width == 320 and cs.height == 260,
        do: %{cs | pos_x: 24 + i * 32, pos_y: 16 + i * 32},
        else: cs
    end)
  end

  describe "sentinel auto-offset" do
    test "offsets sessions that are still at all four schema defaults" do
      cs = %CanvasSession{pos_x: 0, pos_y: 0, width: 320, height: 260}
      [result] = apply_sentinel_offset([cs])
      assert result.pos_x == 24
      assert result.pos_y == 16
    end

    test "preserves a snapped window sitting at pos_x=0, pos_y=0 with non-default size" do
      # Left-half snap: pos_x=0, pos_y=0 but width/height differ from defaults
      cs = %CanvasSession{pos_x: 0, pos_y: 0, width: 500, height: 800}
      [result] = apply_sentinel_offset([cs])
      assert result.pos_x == 0
      assert result.pos_y == 0
      assert result.width == 500
      assert result.height == 800
    end

    test "preserves a window at non-zero position regardless of size" do
      cs = %CanvasSession{pos_x: 100, pos_y: 50, width: 320, height: 260}
      [result] = apply_sentinel_offset([cs])
      assert result.pos_x == 100
      assert result.pos_y == 50
    end

    test "staggers multiple unpositioned windows" do
      sessions = [
        %CanvasSession{pos_x: 0, pos_y: 0, width: 320, height: 260},
        %CanvasSession{pos_x: 0, pos_y: 0, width: 320, height: 260}
      ]

      [first, second] = apply_sentinel_offset(sessions)
      assert first.pos_x == 24
      assert second.pos_x == 56
    end
  end

  describe "Canvases.update_window_layout/2" do
    setup do
      {:ok, canvas} = Canvases.create_canvas(%{name: "test"})

      session =
        EyeInTheSky.Repo.insert!(%EyeInTheSky.Sessions.Session{
          uuid: Ecto.UUID.generate(),
          status: "stopped"
        })

      {:ok, cs} = Canvases.add_session(canvas.id, session.id)
      %{cs: cs}
    end

    test "persists integer layout attrs", %{cs: cs} do
      assert {:ok, updated} =
               Canvases.update_window_layout(cs.id, %{
                 pos_x: 10,
                 pos_y: 20,
                 width: 400,
                 height: 300
               })

      assert updated.pos_x == 10
      assert updated.pos_y == 20
      assert updated.width == 400
      assert updated.height == 300
    end
  end
end
