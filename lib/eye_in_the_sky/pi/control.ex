defmodule EyeInTheSky.Pi.Control do
  @moduledoc """
  One-shot harness IPC for non-chat Pi verbs (spec §4 Pi.Control).

  Each call spawns the harness, performs initialize -> <verb> -> response,
  then tears the process down. Runs inside a Task so harness output never
  lands in the caller's mailbox (LiveViews call this directly).

  OAuth verbs are Phase 3. Credentials go to ~/.pi/agent/auth.json via the
  harness — never through EITS Settings, never logged.
  """

  alias EyeInTheSky.Claude.Utils

  @default_timeout 30_000

  def discover_models(opts \\ []),
    do: one_shot("discover_models", %{}, & &1["models"], opts)

  def list_providers(opts \\ []),
    do: one_shot("list_providers", %{}, & &1, opts)

  def auth_status(opts \\ []),
    do: one_shot("auth_status", %{}, & &1, opts)

  def set_api_key(provider_id, key, opts \\ [])
      when is_binary(provider_id) and is_binary(key) do
    case one_shot("set_api_key", %{providerId: provider_id, key: key}, fn _ -> :ok end, opts) do
      {:ok, :ok} -> :ok
      other -> other
    end
  end

  def clear_api_key(provider_id, opts \\ []) when is_binary(provider_id) do
    case one_shot("clear_api_key", %{providerId: provider_id}, fn _ -> :ok end, opts) do
      {:ok, :ok} -> :ok
      other -> other
    end
  end

  # -- internals ---------------------------------------------------------------

  defp one_shot(command, payload, extract, opts) do
    timeout = opts[:timeout] || @default_timeout

    task =
      Task.async(fn ->
        run_one_shot(command, payload, extract, opts, timeout)
      end)

    Task.await(task, timeout + 5_000)
  catch
    :exit, reason -> {:error, {:pi_control_crashed, reason}}
  end

  defp run_one_shot(command, payload, extract, opts, timeout) do
    cli = Utils.pi_cli_module()
    responder = opts[:responder]

    with {:ok, port, ref} <- cli.spawn_harness(caller: self(), project_path: File.cwd!()) do
      try do
        with {:ok, _} <-
               request(cli, port, ref, %{id: "ctl-1", type: "initialize", protocolVersion: 1}, responder, timeout),
             req <- Map.merge(%{id: "ctl-2", type: command}, payload),
             {:ok, data} <- request(cli, port, ref, req, responder, timeout) do
          {:ok, extract.(data)}
        end
      after
        cli.send_ndjson(port, %{id: "ctl-3", type: "dispose"})
        cli.cancel(port)
      end
    end
  end

  defp request(cli, port, ref, req, responder, timeout) do
    :ok = cli.send_ndjson(port, req)

    if responder do
      case responder.(req) do
        nil -> :ok
        line -> send(self(), {:claude_output, ref, line})
      end
    end

    await_response(ref, req.id, timeout)
  end

  defp await_response(ref, id, timeout) do
    receive do
      {:claude_output, ^ref, line} ->
        case Jason.decode(line) do
          {:ok, %{"type" => "response", "id" => ^id, "success" => true} = r} ->
            {:ok, r["data"]}

          {:ok, %{"type" => "response", "id" => ^id, "success" => false} = r} ->
            {:error, {:pi_control, r["error"]}}

          _other ->
            await_response(ref, id, timeout)
        end

      {:claude_exit, ^ref, code} ->
        {:error, {:harness_exit, code}}
    after
      timeout -> {:error, :pi_control_timeout}
    end
  end
end
