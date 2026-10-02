defmodule EyeInTheSky.Codex.EitsUrlInjectionTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Codex.AppServer.Protocol
  alias EyeInTheSky.Codex.CLI

  @eits_url "http://127.0.0.1:34878/api/v1"

  test "codex exec exposes EITS_URL to agent shell commands" do
    args = CLI.build_args(prompt: "hello", eits_url: @eits_url)

    assert Enum.chunk_every(args, 2, 1, :discard)
           |> Enum.any?(
             &(&1 == [
                 "-c",
                 ~s(shell_environment_policy.set.EITS_URL="#{@eits_url}")
               ])
           )
  end

  test "codex app-server exposes EITS_URL to thread shell commands" do
    request =
      Protocol.thread_start_request(1,
        project_path: "/tmp",
        eits_url: @eits_url
      )

    env = request["params"]["config"]["shell_environment_policy"]["set"]

    assert env["EITS_URL"] == @eits_url
  end
end
