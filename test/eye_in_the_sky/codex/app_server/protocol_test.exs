defmodule EyeInTheSky.Codex.AppServer.ProtocolTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Codex.AppServer.Protocol

  test "parses JSON-RPC message shapes" do
    assert {:ok, {:response, %{"id" => 1}}} =
             Protocol.parse_line(~s({"jsonrpc":"2.0","id":1,"result":{"ok":true}}))

    assert {:ok, {:error, %{"id" => "req-1"}}} =
             Protocol.parse_line(~s({"jsonrpc":"2.0","id":"req-1","error":{"message":"bad"}}))

    assert {:ok, {:notification, %{"method" => "turn/completed"}}} =
             Protocol.parse_line(~s({"jsonrpc":"2.0","method":"turn/completed","params":{}}))

    assert {:ok, {:request, %{"method" => "item/tool/requestUserInput"}}} =
             Protocol.parse_line(
               ~s({"jsonrpc":"2.0","id":"ask-1","method":"item/tool/requestUserInput","params":{}})
             )
  end

  test "skips non-json preamble lines" do
    assert :skip = Protocol.parse_line("Codex app-server starting")
  end

  test "builds thread and turn requests with EITS shell environment policy" do
    request =
      Protocol.thread_start_request(1,
        model: "gpt-5.2",
        project_path: "/tmp",
        bypass_sandbox: true,
        eits_session_id: 123,
        eits_session_uuid: "session-uuid",
        eits_project_id: 9,
        eits_model: "gpt-5.2"
      )

    assert request["method"] == "thread/start"
    assert request["params"]["model"] == "gpt-5.2-codex"
    assert request["params"]["approvalPolicy"] == "never"
    assert request["params"]["sandbox"] == "danger-full-access"

    env = request["params"]["config"]["shell_environment_policy"]["set"]
    assert env["EITS_SESSION_ID"] == "123"
    assert env["EITS_SESSION_UUID"] == "session-uuid"
    assert env["EITS_PROJECT_ID"] == "9"

    turn = Protocol.turn_start_request(2, "thread-1", "hello", project_path: "/tmp")

    assert turn["method"] == "turn/start"
    assert turn["params"]["threadId"] == "thread-1"
    assert [%{"type" => "text", "text" => "hello"}] = turn["params"]["input"]
    assert turn["params"]["sandboxPolicy"]["type"] == "dangerFullAccess"
  end

  test "server request responses decline approvals and answer user input" do
    command =
      Protocol.server_request_response(%{
        "id" => 8,
        "method" => "item/commandExecution/requestApproval",
        "params" => %{}
      })

    assert command["id"] == 8
    assert command["result"] == %{"decision" => "decline"}

    input =
      Protocol.server_request_response(%{
        "id" => "ask-1",
        "method" => "item/tool/requestUserInput",
        "params" => %{"questions" => [%{"id" => "q1", "question" => "Continue?"}]}
      })

    assert input["id"] == "ask-1"
    assert input["result"] == %{"answers" => %{"q1" => %{"answers" => []}}}
  end
end
