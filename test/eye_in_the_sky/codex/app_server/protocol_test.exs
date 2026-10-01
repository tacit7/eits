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

  test "builds hooks/list requests for one or more cwd values" do
    request = Protocol.hooks_list_request("hooks-1", ["/tmp/project"])

    assert request["id"] == "hooks-1"
    assert request["method"] == "hooks/list"
    assert request["params"] == %{"cwds" => ["/tmp/project"]}
  end

  test "server request responses decline approvals, user input, and MCP elicitation" do
    assert Protocol.server_request_response(%{
             "id" => 8,
             "method" => "item/commandExecution/requestApproval",
             "params" => %{}
           })["result"] == %{"decision" => "decline"}

    assert Protocol.server_request_response(%{
             "id" => "file-1",
             "method" => "item/fileChange/requestApproval",
             "params" => %{}
           })["result"] == %{"decision" => "decline"}

    assert Protocol.server_request_response(%{
             "id" => "permissions-1",
             "method" => "item/permissions/requestApproval",
             "params" => %{}
           })["result"] == %{"permissions" => %{}, "scope" => "turn"}

    assert Protocol.server_request_response(%{
             "id" => "ask-1",
             "method" => "tool/requestUserInput",
             "params" => %{"questions" => [%{"id" => "q1", "question" => "Continue?"}]}
           })["result"] == %{"answers" => %{"q1" => %{"answers" => []}}}

    assert Protocol.server_request_response(%{
             "id" => "ask-legacy",
             "method" => "item/tool/requestUserInput",
             "params" => %{"questions" => [%{"id" => "q2", "question" => "Continue?"}]}
           })["result"] == %{"answers" => %{"q2" => %{"answers" => []}}}

    assert Protocol.server_request_response(%{
             "id" => "mcp-1",
             "method" => "mcpServer/elicitation/request",
             "params" => %{}
           })["result"] == %{"action" => "decline", "content" => nil, "_meta" => nil}
  end

  test "server request metadata classifies known and unknown requests" do
    metadata =
      Protocol.server_request_metadata(%{
        "id" => "approval-1",
        "method" => "item/commandExecution/requestApproval",
        "params" => %{
          "threadId" => "thread-1",
          "turnId" => "turn-1",
          "itemId" => "cmd-1",
          "autoResolutionMs" => 1_000
        }
      })

    assert metadata == %{
             request_id: "approval-1",
             method: "item/commandExecution/requestApproval",
             category: :command_approval,
             thread_id: "thread-1",
             turn_id: "turn-1",
             item_id: "cmd-1",
             server_name: nil,
             auto_resolution_ms: 1_000,
             response_type: :result
           }

    assert %{
             category: :unknown,
             response_type: :error
           } =
             Protocol.server_request_metadata(%{
               "id" => "unknown-1",
               "method" => "item/tool/call",
               "params" => %{}
             })
  end

  test "unknown server requests produce JSON-RPC method errors" do
    response =
      Protocol.server_request_response(%{
        "id" => "unknown-1",
        "method" => "item/tool/call",
        "params" => %{}
      })

    assert response["id"] == "unknown-1"
    assert response["error"]["code"] == -32601
    assert response["error"]["message"] =~ "item/tool/call"
  end
end
