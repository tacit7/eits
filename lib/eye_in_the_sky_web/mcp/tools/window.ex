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

  @impl true
  def execute(_params, frame) do
    result =
      case System.cmd("osascript", ["-e", @applescript], stderr_to_stdout: true) do
        {output, 0} ->
          [app | rest] = String.split(String.trim(output), "|", parts: 2)
          window_title = List.first(rest, "")

          %{
            success: true,
            message: "Window info retrieved",
            application: app,
            window_title: window_title
          }

        {err, _} ->
          %{success: false, message: "Failed to get window info: #{String.trim(err)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
