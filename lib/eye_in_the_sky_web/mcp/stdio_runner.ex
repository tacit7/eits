defmodule EyeInTheSkyWeb.MCP.StdioRunner do
  @moduledoc """
  Simple stdio transport for the EITS MCP server.

  Reads JSON-RPC messages from stdin, forwards to the MCP server,
  and writes responses to stdout.
  """

  require Logger

  @doc """
  Starts the stdio loop.
  Reads from stdin, processes messages, writes to stdout.
  """
  def run do
    # Start the application if not already started
    Application.ensure_all_started(:eye_in_the_sky_web)

    Logger.info("EITS MCP stdio server starting...")

    # Process stdin line by line
    stdin_loop()
  end

  defp stdin_loop do
    case IO.read(:stdio, :line) do
      :eof ->
        Logger.info("Stdin closed, shutting down")
        :ok

      {:error, reason} ->
        Logger.error("Error reading stdin: #{inspect(reason)}")
        :ok

      line when is_binary(line) ->
        line = String.trim(line)

        if line != "" do
          process_line(line)
        end

        stdin_loop()
    end
  end

  defp process_line(line) do
    case Jason.decode(line) do
      {:ok, message} when is_map(message) ->
        handle_message(message)

      {:ok, messages} when is_list(messages) ->
        # Handle batch of messages
        Enum.each(messages, &handle_message/1)

      {:error, reason} ->
        Logger.error("Failed to parse JSON: #{inspect(reason)}")
        send_error_response(nil, -32700, "Parse error")
    end
  end

  defp handle_message(%{"method" => method, "id" => id} = message) do
    Logger.debug("Received request: #{method}")

    case route_message(message) do
      {:ok, response} ->
        send_response(id, response)

      {:error, error} ->
        send_error_response(id, error["code"] || -32603, error["message"] || "Internal error")
    end
  end

  defp handle_message(%{"method" => method} = message) do
    # Notification (no id field)
    Logger.debug("Received notification: #{method}")
    route_message(message)
    :ok
  end

  defp handle_message(message) do
    Logger.warn("Invalid message format: #{inspect(message)}")
    :ok
  end

  defp route_message(%{"method" => "initialize", "params" => params, "id" => id}) do
    # MCP initialize handshake
    response = %{
      protocolVersion: "2024-11-05",
      capabilities: %{
        tools: %{}
      },
      serverInfo: %{
        name: "eits",
        version: "1.0.0"
      }
    }

    {:ok, response}
  end

  defp route_message(%{"method" => "tools/list", "id" => _id}) do
    # List all available tools
    tools =
      Anubis.Server.list_components(EyeInTheSkyWeb.MCP.Server, :tool)
      |> Enum.map(fn {name, module} ->
        schema = module.__schema__()

        %{
          name: name,
          description: module.__moduledoc__() || "",
          inputSchema: %{
            type: "object",
            properties: schema_to_json_schema(schema),
            required: required_fields(schema)
          }
        }
      end)

    {:ok, %{tools: tools}}
  end

  defp route_message(%{"method" => "tools/call", "params" => params, "id" => _id}) do
    tool_name = params["name"]
    arguments = params["arguments"] || %{}

    case Anubis.Server.call_component(
           EyeInTheSkyWeb.MCP.Server,
           tool_name,
           arguments,
           %{type: :stdio}
         ) do
      {:ok, result} ->
        {:ok, %{content: [%{type: "text", text: format_result(result)}]}}

      {:error, reason} ->
        {:error, %{"code" => -32603, "message" => inspect(reason)}}
    end
  end

  defp route_message(%{"method" => method}) do
    Logger.warn("Unknown method: #{method}")
    {:error, %{"code" => -32601, "message" => "Method not found"}}
  end

  defp send_response(id, result) do
    response = %{
      jsonrpc: "2.0",
      id: id,
      result: result
    }

    json = Jason.encode!(response)
    IO.puts(json)
  end

  defp send_error_response(id, code, message) do
    response = %{
      jsonrpc: "2.0",
      id: id,
      error: %{
        code: code,
        message: message
      }
    }

    json = Jason.encode!(response)
    IO.puts(json)
  end

  defp schema_to_json_schema(schema) do
    Enum.reduce(schema, %{}, fn {name, field_schema}, acc ->
      Map.put(acc, name, %{
        type: elixir_type_to_json_type(field_schema[:type]),
        description: field_schema[:description] || ""
      })
    end)
  end

  defp required_fields(schema) do
    schema
    |> Enum.filter(fn {_name, field_schema} -> field_schema[:required] end)
    |> Enum.map(fn {name, _} -> to_string(name) end)
  end

  defp elixir_type_to_json_type(:string), do: "string"
  defp elixir_type_to_json_type(:integer), do: "integer"
  defp elixir_type_to_json_type(:boolean), do: "boolean"
  defp elixir_type_to_json_type(_), do: "string"

  defp format_result(result) when is_binary(result), do: result
  defp format_result(result) when is_map(result), do: Jason.encode!(result)
  defp format_result(result), do: inspect(result)
end
