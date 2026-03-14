defmodule EyeInTheSkyWeb.MCP.Tools.ChatChannelList do
  @moduledoc "List available chat channels"

  use Anubis.Server.Component, type: :tool

  alias EyeInTheSkyWeb.MCP.Tools.ResponseHelper

  schema do
    field :project_id, :integer, description: "Filter by project ID (optional)"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Channels

    channels =
      if params[:project_id] do
        Channels.list_channels_for_project(params[:project_id])
      else
        Channels.list_channels()
      end

    result = %{
      success: true,
      message: "#{length(channels)} channel(s) found",
      channels:
        Enum.map(channels, fn ch ->
          %{
            id: to_string(ch.id),
            name: ch.name,
            description: ch.description,
            channel_type: ch.channel_type,
            project_id: ch.project_id
          }
        end)
    }

    response = ResponseHelper.json_response(result)
    {:reply, response, frame}
  end
end
