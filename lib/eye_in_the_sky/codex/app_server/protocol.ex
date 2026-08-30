defmodule EyeInTheSky.Codex.AppServer.Protocol do
  @moduledoc """
  JSON-RPC helpers for the Codex `app-server --listen stdio://` protocol.

  This module is intentionally separate from `EyeInTheSky.Codex.Parser`: the
  app-server stream is JSON-RPC with camelCase notification names, while
  `codex exec --json` is JSONL with dot-separated event names.
  """

  @type id :: integer() | String.t()
  @type json :: map() | list() | String.t() | number() | boolean() | nil

  @spec parse_line(String.t()) ::
          {:ok, {:request | :response | :error | :notification, map()}} | :skip | {:error, term()}
  def parse_line(line) when is_binary(line) do
    line = String.trim(line)

    cond do
      line == "" ->
        :skip

      not String.starts_with?(line, "{") ->
        :skip

      true ->
        with {:ok, message} <- Jason.decode(line),
             {:ok, routed} <- route(message) do
          {:ok, routed}
        end
    end
  end

  @spec request(id(), String.t(), map() | nil) :: map()
  def request(id, method, params \\ nil) do
    %{"jsonrpc" => "2.0", "id" => id, "method" => method}
    |> maybe_put("params", params)
  end

  @spec notification(String.t(), map() | nil) :: map()
  def notification(method, params \\ nil) do
    %{"jsonrpc" => "2.0", "method" => method}
    |> maybe_put("params", params)
  end

  @spec result(id(), json()) :: map()
  def result(id, payload), do: %{"jsonrpc" => "2.0", "id" => id, "result" => payload}

  @spec error(id() | nil, integer(), String.t()) :: map()
  def error(id, code, message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end

  @spec encode!(map()) :: iodata()
  def encode!(message), do: [Jason.encode!(message), "\n"]

  @spec initialize_request(id(), String.t()) :: map()
  def initialize_request(id, version) do
    request(id, "initialize", %{
      "clientInfo" => %{"name" => "eits", "title" => "EITS", "version" => version},
      "capabilities" => %{"experimentalApi" => true}
    })
  end

  @spec initialized_notification() :: map()
  def initialized_notification, do: notification("initialized")

  @spec thread_start_request(id(), keyword()) :: map()
  def thread_start_request(id, opts) do
    request(id, "thread/start", thread_params(opts))
  end

  @spec thread_resume_request(id(), String.t(), keyword()) :: map()
  def thread_resume_request(id, thread_id, opts) do
    request(id, "thread/resume", Map.put(thread_params(opts), "threadId", thread_id))
  end

  @spec turn_start_request(id(), String.t(), String.t(), keyword()) :: map()
  def turn_start_request(id, thread_id, prompt, opts) do
    request(id, "turn/start", %{
      "threadId" => thread_id,
      "input" => [%{"type" => "text", "text" => prompt, "textElements" => []}],
      "cwd" => opts[:project_path] || File.cwd!(),
      "approvalPolicy" => approval_policy(opts),
      "approvalsReviewer" => "user",
      "sandboxPolicy" => sandbox_policy(opts),
      "model" => model(opts),
      "effort" => reasoning_effort(opts)
    })
  end

  @spec turn_interrupt_request(id(), String.t(), String.t()) :: map()
  def turn_interrupt_request(id, thread_id, turn_id) do
    request(id, "turn/interrupt", %{"threadId" => thread_id, "turnId" => turn_id})
  end

  @spec server_request_response(map()) :: map()
  def server_request_response(%{"id" => id, "method" => method} = request) do
    params = request["params"] || %{}

    payload =
      case method do
        "item/commandExecution/requestApproval" ->
          %{"decision" => "decline"}

        "item/fileChange/requestApproval" ->
          %{"decision" => "decline"}

        "item/permissions/requestApproval" ->
          %{"permissions" => %{}, "scope" => "turn"}

        "item/tool/requestUserInput" ->
          %{"answers" => empty_answers(params["questions"])}

        "mcpServer/elicitation/request" ->
          %{"action" => "decline", "content" => nil, "_meta" => nil}

        _ ->
          nil
      end

    if payload do
      result(id, payload)
    else
      error(id, -32601, "Codex app-server request `#{method}` is not implemented")
    end
  end

  defp route(%{"id" => _id, "method" => _method, "params" => _params} = message),
    do: {:ok, {:request, message}}

  defp route(%{"id" => _id, "method" => _method} = message), do: {:ok, {:request, message}}
  defp route(%{"method" => _method} = message), do: {:ok, {:notification, message}}
  defp route(%{"id" => _id, "result" => _result} = message), do: {:ok, {:response, message}}
  defp route(%{"id" => _id, "error" => _error} = message), do: {:ok, {:error, message}}
  defp route(%{"error" => _error} = message), do: {:ok, {:error, message}}
  defp route(_), do: {:error, :unknown_jsonrpc_message}

  defp thread_params(opts) do
    %{
      "model" => model(opts),
      "modelProvider" => "openai",
      "cwd" => opts[:project_path] || File.cwd!(),
      "approvalPolicy" => approval_policy(opts),
      "approvalsReviewer" => "user",
      "sandbox" => thread_sandbox(opts),
      "threadSource" => "user",
      "config" => thread_config(opts)
    }
  end

  defp thread_config(opts) do
    env =
      [
        {"EITS_SESSION_UUID", opts[:eits_session_uuid]},
        {"EITS_SESSION_ID", opts[:eits_session_id]},
        {"EITS_AGENT_UUID", opts[:eits_agent_uuid]},
        {"EITS_AGENT_ID", opts[:eits_agent_id]},
        {"EITS_PROJECT_ID", opts[:eits_project_id]},
        {"EITS_CHANNEL_ID", opts[:eits_channel_id]},
        {"EITS_MODEL", opts[:eits_model]},
        {"ENTRYPOINT", opts[:entrypoint] || "cli"},
        {"EITS_URL",
         opts[:eits_url] || System.get_env("EITS_URL", "http://localhost:5001/api/v1")}
      ]
      |> Enum.flat_map(fn
        {_key, nil} -> []
        {_key, ""} -> []
        {key, value} when is_binary(value) or is_integer(value) -> [{key, to_string(value)}]
        {key, value} when is_atom(value) -> [{key, Atom.to_string(value)}]
        _other -> []
      end)
      |> Map.new()

    config =
      %{}
      |> maybe_put("model_reasoning_effort", reasoning_effort(opts))
      |> maybe_put("shell_environment_policy", if(map_size(env) > 0, do: %{"set" => env}))

    if map_size(config) == 0, do: nil, else: config
  end

  defp model(opts) do
    case opts[:model] do
      "gpt-5.2" -> "gpt-5.2-codex"
      nil -> nil
      model -> to_string(model)
    end
  end

  defp reasoning_effort(opts) do
    case opts[:reasoning_effort] || opts[:effort] do
      nil -> nil
      effort when effort in ["low", "medium", "high", "xhigh"] -> effort
      effort when effort in ["auto", "default", "none", "minimal", "max"] -> "high"
      effort when is_binary(effort) -> effort |> String.trim() |> empty_to_nil()
      effort -> to_string(effort)
    end
  end

  defp approval_policy(opts) do
    cond do
      Keyword.get(opts, :bypass_sandbox, true) -> "never"
      opts[:ask_for_approval] == "never" -> "never"
      true -> "on-request"
    end
  end

  defp thread_sandbox(opts) do
    cond do
      Keyword.get(opts, :bypass_sandbox, true) -> "danger-full-access"
      opts[:sandbox] -> to_string(opts[:sandbox])
      true -> "workspace-write"
    end
  end

  defp sandbox_policy(opts) do
    cond do
      Keyword.get(opts, :bypass_sandbox, true) ->
        %{"type" => "dangerFullAccess"}

      opts[:sandbox] == "read-only" ->
        %{"type" => "readOnly", "networkAccess" => false}

      true ->
        %{"type" => "workspaceWrite", "networkAccess" => false}
    end
  end

  defp empty_answers(questions) when is_list(questions) do
    questions
    |> Enum.map(fn
      %{"id" => id} when is_binary(id) -> {id, %{"answers" => []}}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp empty_answers(_), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
