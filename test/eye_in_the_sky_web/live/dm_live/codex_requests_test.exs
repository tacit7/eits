defmodule EyeInTheSkyWeb.DmLive.CodexRequestsTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EyeInTheSky.Codex.AppServer
  alias EyeInTheSky.Factory

  test "a pending Codex approval survives mount and can be answered", %{conn: conn} do
    agent = Factory.create_agent()
    session = Factory.create_session(agent, %{provider: "codex"})

    {:ok, server} =
      AppServer.lookup_or_start(session.id,
        project_path: "/tmp",
        transport_pid: self()
      )

    on_exit(fn -> AppServer.stop_owner(session.id) end)
    ref = start_turn(server, session.id)
    {:ok, open_view, _html} = live(conn, "/dm/#{session.uuid}")
    refute has_element?(open_view, "#codex-requests")

    notify(server, "item/started", %{
      "threadId" => "thread-dm",
      "turnId" => "turn-dm",
      "item" => %{"id" => "cmd-1", "type" => "commandExecution", "command" => "git status"}
    })

    send(server, {
      :codex_app_server_output,
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => "approval-dm",
        "method" => "item/commandExecution/requestApproval",
        "params" => %{
          "threadId" => "thread-dm",
          "turnId" => "turn-dm",
          "itemId" => "cmd-1"
        }
      })
    })

    assert [%{"id" => "approval-dm"}] = AppServer.pending_server_requests(session.id)
    assert has_element?(open_view, "#codex-requests")

    {:ok, view, _html} = live(conn, "/dm/#{session.uuid}")
    assert has_element?(view, "#codex-requests")

    assert has_element?(
             view,
             "#codex-request-form-#{Base.url_encode64("approval-dm", padding: false)} button[value='accept']"
           )

    render_submit(view, "codex_request_answer", %{
      "approval" => %{"request_id" => "approval-dm", "action" => "accept"}
    })

    assert_receive {:codex_app_server_write, ^server, response_json}

    assert %{"id" => "approval-dm", "result" => %{"decision" => "accept"}} =
             Jason.decode!(response_json)

    refute has_element?(view, "#codex-requests")

    notify(server, "turn/completed", %{
      "threadId" => "thread-dm",
      "turn" => %{"id" => "turn-dm", "status" => "completed"}
    })

    assert_receive {:claude_complete, ^ref, "thread-dm"}
  end

  defp start_turn(server, session_id) do
    ref = make_ref()
    caller = self()

    task =
      Task.async(fn ->
        AppServer.start_turn(server, ref, caller, "hello",
          project_path: "/tmp",
          eits_session_id: session_id
        )
      end)

    assert_receive {:codex_app_server_write, ^server, init_json}
    %{"id" => init_id, "method" => "initialize"} = Jason.decode!(init_json)
    respond(server, init_id, %{})

    assert_receive {:codex_app_server_write, ^server, initialized_json}
    assert %{"method" => "initialized"} = Jason.decode!(initialized_json)

    assert_receive {:codex_app_server_write, ^server, thread_json}
    %{"id" => thread_id, "method" => "thread/start"} = Jason.decode!(thread_json)
    respond(server, thread_id, %{"thread" => %{"id" => "thread-dm"}})
    assert_receive {:codex_session_id, ^ref, "thread-dm"}

    assert_receive {:codex_app_server_write, ^server, turn_json}
    %{"id" => turn_id, "method" => "turn/start"} = Jason.decode!(turn_json)
    respond(server, turn_id, %{"turn" => %{"id" => "turn-dm"}})
    assert {:ok, ^ref, ^server} = Task.await(task)
    ref
  end

  defp respond(server, id, result) do
    send(server, {
      :codex_app_server_output,
      Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => result})
    })
  end

  defp notify(server, method, params) do
    send(server, {
      :codex_app_server_output,
      Jason.encode!(%{"jsonrpc" => "2.0", "method" => method, "params" => params})
    })
  end
end
