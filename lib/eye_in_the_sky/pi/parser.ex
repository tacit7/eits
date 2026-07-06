defmodule EyeInTheSky.Pi.Parser do
  @moduledoc """
  Parses ndjson lines from the Pi harness sidecar.

  Protocol reference: docs/superpowers/specs/2026-07-06-pi-integration-design.md §3.
  Request/response envelopes, `ready`, `tool_request`, `turn_error`, and `exit`
  surface as `{:protocol, map}` for Pi.SDK bookkeeping; streaming content maps
  to Claude.Message structs for the shared pipeline.
  """

  alias EyeInTheSky.Claude.Message
  require Logger

  @protocol_types ~w(response ready tool_request turn_error exit)

  @spec parse_stream_line(String.t()) ::
          {:ok, Message.t()} | {:protocol, map()} | {:result, map()} | {:error, term()} | :skip
  def parse_stream_line(line) when is_binary(line) do
    case String.trim(line) do
      "" ->
        :skip

      trimmed ->
        case Jason.decode(trimmed) do
          {:ok, json} -> parse_event(json)
          {:error, _} -> :skip
        end
    end
  end

  defp parse_event(%{"type" => type} = event) when type in @protocol_types, do: {:protocol, event}

  defp parse_event(%{"type" => "assistant_delta", "delta" => delta}) when is_binary(delta),
    do: {:ok, Message.text(delta, true)}

  defp parse_event(%{"type" => "thinking_delta", "delta" => delta}) when is_binary(delta),
    do: {:ok, Message.thinking(delta, true)}

  defp parse_event(%{"type" => "turn_start"}), do: :skip

  defp parse_event(%{"type" => "tool_update"} = event) do
    input = event["args"] || %{}

    {:ok,
     Message.tool_use(
       event["toolName"] || "tool",
       input,
       %{partial: true, tool_call_id: event["toolCallId"], phase: event["phase"]}
     )}
  end

  defp parse_event(%{"type" => "tool_result"} = event) do
    input = %{"result" => event["result"], "isError" => event["isError"]}

    {:ok,
     Message.tool_use(
       event["toolName"] || "tool",
       input,
       %{tool_call_id: event["toolCallId"]}
     )}
  end

  defp parse_event(%{"type" => "turn_end"} = event) do
    aggregate = event["aggregate"] || %{}

    {:result,
     %{
       input_tokens: aggregate["inputTokens"] || 0,
       output_tokens: aggregate["outputTokens"] || 0,
       usage: aggregate,
       iteration: event["iteration"],
       total_cost_usd: event["totalCostUsd"],
       duration_ms: event["durationMs"],
       error: event["error"]
     }}
  end

  defp parse_event(%{"type" => "compaction_start"} = event),
    do: {:ok, Message.text("[compacting context: #{event["reason"]}]", false)}

  defp parse_event(%{"type" => "compaction_end"} = event) do
    status = if event["aborted"], do: "aborted", else: "done"
    {:ok, Message.text("[compaction #{status}]", false)}
  end

  defp parse_event(%{"type" => "error"} = event),
    do: {:error, {:pi_error, event["error"] || "unknown Pi error"}}

  defp parse_event(other) do
    Logger.debug("[Pi.Parser] Unhandled event type: #{inspect(other["type"])}")
    :skip
  end
end
