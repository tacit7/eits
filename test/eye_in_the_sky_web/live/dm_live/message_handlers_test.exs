defmodule EyeInTheSkyWeb.DmLive.MessageHandlersTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.{Factory, Repo}
  alias EyeInTheSkyWeb.DmLive.MessageHandlers

  # Builds a minimal disconnected socket (connected? returns false).
  defp build_socket(assigns) do
    base = %{
      __changed__: %{},
      active_tab: "messages",
      message_limit: 20,
      message_search_query: nil
    }

    %Phoenix.LiveView.Socket{assigns: Map.merge(base, assigns)}
  end

  describe "load_messages_on_mount/1" do
    test "when not connected: loads messages via TabHelpers without sync" do
      agent = Factory.create_agent() |> Repo.preload(:project)
      session = Factory.create_session(agent)

      socket =
        build_socket(%{
          session_id: session.id,
          session_uuid: session.uuid,
          session: session,
          agent: agent
        })

      # Not connected (transport_pid: nil), so should fall back to DB load.
      result = MessageHandlers.load_messages_on_mount(socket)

      # TabHelpers.load_tab_data assigns :messages — verify the socket was updated.
      assert Map.has_key?(result.assigns, :messages)
    end
  end
end
