defmodule EyeInTheSky.Pi.ControlTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Pi.Control

  defmodule StubCLI do
    def start_link, do: Agent.start_link(fn -> [] end, name: __MODULE__)
    def sends, do: Agent.get(__MODULE__, & &1) |> Enum.reverse()

    def spawn_harness(opts) do
      send(self(), {:harness_spawned, opts[:caller]})
      {:ok, spawn(fn -> receive do: (:never -> :ok) end), make_ref()}
    end

    def send_ndjson(_port, map) do
      Agent.update(__MODULE__, &[map | &1])
      :ok
    end

    def cancel(_port), do: :ok
  end

  setup do
    Application.put_env(:eye_in_the_sky, :pi_cli_module, StubCLI)

    # Guard against a dead-but-registered name from a prior test.
    case Process.whereis(StubCLI) do
      nil ->
        :ok

      pid ->
        Process.exit(pid, :kill)
        wait_gone(StubCLI)
    end

    {:ok, _} = StubCLI.start_link()

    on_exit(fn ->
      Application.delete_env(:eye_in_the_sky, :pi_cli_module)

      case Process.whereis(StubCLI) do
        nil -> :ok
        pid -> Process.exit(pid, :kill)
      end
    end)

    :ok
  end

  defp wait_gone(name) do
    case Process.whereis(name) do
      nil ->
        :ok

      _ ->
        Process.sleep(5)
        wait_gone(name)
    end
  end

  test "discover_models sends initialize then discover_models with ctl ids" do
    responder = fn %{id: id, type: type} ->
      data =
        case type do
          "initialize" ->
            ~s({"protocolVersion":1})

          "discover_models" ->
            ~s({"models":[{"id":"ollama-lan/qwen3.6:27b","provider":"ollama-lan"}]})
        end

      ~s({"id":"#{id}","type":"response","command":"#{type}","success":true,"data":#{data}})
    end

    assert {:ok, [%{"id" => "ollama-lan/qwen3.6:27b"}]} =
             Control.discover_models(responder: responder)

    types = StubCLI.sends() |> Enum.map(& &1.type)
    assert types == ["initialize", "discover_models", "dispose"]
  end

  test "failed response surfaces the harness error" do
    responder = fn %{id: id, type: type} ->
      case type do
        "initialize" ->
          ~s({"id":"#{id}","type":"response","command":"initialize","success":true,"data":{"protocolVersion":1}})

        "set_api_key" ->
          ~s({"id":"#{id}","type":"response","command":"set_api_key","success":false,"error":"unknown provider"})
      end
    end

    assert {:error, {:pi_control, "unknown provider"}} =
             Control.set_api_key("nope", "sk-x", responder: responder)
  end

  test "set_api_key sends providerId and key, returns :ok on success" do
    responder = fn %{id: id, type: type} ->
      ~s({"id":"#{id}","type":"response","command":"#{type}","success":true,"data":true})
    end

    assert :ok = Control.set_api_key("openrouter", "sk-or-123", responder: responder)

    assert %{type: "set_api_key", providerId: "openrouter", key: "sk-or-123"} =
             Enum.find(StubCLI.sends(), &(&1.type == "set_api_key"))
  end

  test "harness error strings that echo key material are redacted at the boundary" do
    submitted_key = "sk-or-abc123def456ghi789xyz"

    responder = fn %{id: id, type: type} ->
      case type do
        "initialize" ->
          ~s({"id":"#{id}","type":"response","command":"initialize","success":true,"data":{"protocolVersion":1}})

        "set_api_key" ->
          ~s({"id":"#{id}","type":"response","command":"set_api_key","success":false,"error":"invalid key #{submitted_key}"})
      end
    end

    assert {:error, {:pi_control, msg}} =
             Control.set_api_key("echo", submitted_key, responder: responder)

    refute msg =~ submitted_key
    refute msg =~ "sk-or-abc123"
    assert msg =~ "[redacted]"
  end

  test "timeout returns error" do
    responder = fn
      %{type: "initialize", id: id} ->
        ~s({"id":"#{id}","type":"response","command":"initialize","success":true,"data":{"protocolVersion":1}})

      _ ->
        nil
    end

    assert {:error, :pi_control_timeout} =
             Control.discover_models(responder: responder, timeout: 200)
  end
end
