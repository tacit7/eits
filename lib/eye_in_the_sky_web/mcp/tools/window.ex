defmodule EyeInTheSkyWeb.MCP.Tools.Window do
  @moduledoc "Get current active window info (macOS)"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :_placeholder, :string, description: "No parameters needed"
  end

  @applescript """
  tell application "System Events"
    set frontApp to name of first process whose frontmost is true
    set windowTitle to ""
    try
      tell process frontApp
        set windowTitle to name of front window
      end tell
    end try
    return frontApp & "|" & windowTitle
  end tell
  """

  @timeout_ms 3_000

  @impl true
  def execute(_params, frame) do
    task =
      Task.async(fn ->
        System.cmd("osascript", ["-e", @applescript], stderr_to_stdout: true)
      end)

    result =
      case Task.yield(task, @timeout_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, {output, 0}} ->
          [app | rest] = String.split(String.trim(output), "|", parts: 2)
          window_title = List.first(rest, "")

          %{
            success: true,
            message: "Window info retrieved",
            application: app,
            window_title: window_title
          }

        {:ok, {err, _}} ->
          %{success: false, message: "Failed to get window info: #{String.trim(err)}"}

        nil ->
          %{success: false, message: "osascript timed out after #{@timeout_ms}ms"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
