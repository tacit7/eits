defmodule EyeInTheSkyWeb.DmLive.CodexControlsTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias EyeInTheSky.Factory

  test "Codex sessions use the model displayed by the composer for missing and stale models", %{
    conn: conn
  } do
    agent = Factory.create_agent()

    for model <- [nil, "gpt-5.2"] do
      session = Factory.create_session(agent, %{provider: "codex", model: model, status: "idle"})
      {:ok, view, _} = live(conn, "/dm/#{session.id}")
      assert has_element?(view, "#composer-model-selector[data-selected-model='gpt-6-astra']")

      # Settings reads the actual server selection; the composer may format it.
      render_click(view, "change_tab", %{"tab" => "settings"})
      assert has_element?(view, "#dm-settings-tab", "gpt-6-astra")
    end
  end

  test "changing the Codex model preserves the selected reasoning effort", %{conn: conn} do
    agent = Factory.create_agent()

    session =
      Factory.create_session(agent, %{provider: "codex", model: "gpt-6-astra", status: "idle"})

    {:ok, view, _} = live(conn, "/dm/#{session.id}")

    view |> element("#reasoning-pill-effort-relative") |> render_click()
    view |> element("#reasoning-pill-effort-menu [phx-value-effort='xhigh']") |> render_click()
    assert has_element?(view, "#reasoning-pill-effort-button", "XHigh")

    render_click(view, "select_model", %{"provider" => "codex", "model" => "gpt-6-sol"})
    assert has_element?(view, "#composer-model-selector[data-selected-model='gpt-6-sol']")
    assert has_element?(view, "#reasoning-pill-effort-button", "XHigh")
  end
end
