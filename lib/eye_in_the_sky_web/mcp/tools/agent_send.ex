defmodule EyeInTheSkyWeb.MCP.Tools.AgentSend do
  @moduledoc "Send a message to an agent worker by session ID (int or UUID)"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EyeInTheSkyWeb.MCP.Tools.Helpers

  schema do
    field :session_id, :string,
      required: true,
      description: "Target session ID (integer or UUID)"

    field :message, :string, required: true, description: "Message to send to the agent worker"

    field :model, :string,
      description: "Model override (haiku, sonnet, opus). Uses session default if omitted."

    field :effort_level, :string,
      description: "Effort level override. Uses session default if omitted."
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Claude.AgentManager

    result =
      case Helpers.resolve_session_int_id(params[:session_id]) do
        {:ok, int_id} ->
          opts =
            []
            |> maybe_put(:model, params[:model])
            |> maybe_put(:effort_level, params[:effort_level])

          case AgentManager.send_message(int_id, params[:message], opts) do
            :ok ->
              %{success: true, message: "Message queued for session #{int_id}"}

            {:error, reason} ->
              %{success: false, message: "Failed: #{inspect(reason)}"}
          end

        {:error, reason} ->
          %{success: false, message: reason}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
