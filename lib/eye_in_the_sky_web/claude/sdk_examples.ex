defmodule EyeInTheSkyWeb.Claude.SDKExamples do
  @moduledoc """
  Usage examples for the Claude Code SDK.

  These examples show how to use the SDK in different scenarios.
  """

  alias EyeInTheSkyWeb.Claude.{SDK, Message}

  @doc """
  Simple one-shot request with streaming output.

  Starts a Claude session, collects all text output, and returns it as a string.
  """
  def simple_request(prompt, opts \\ []) do
    {:ok, ref} = SDK.start(prompt, Keyword.put(opts, :to, self()))

    collect_text(ref, [])
  end

  defp collect_text(ref, acc) do
    receive do
      {:claude_message, ^ref, %Message{type: :text, content: text}} ->
        collect_text(ref, [text | acc])

      {:claude_complete, ^ref, _session_id} ->
        acc |> Enum.reverse() |> Enum.join()

      {:claude_error, ^ref, reason} ->
        {:error, reason}
    after
      120_000 -> {:error, :timeout}
    end
  end

  @doc """
  Multi-turn conversation example.

  Shows how to manage session_id manually for multi-turn conversations.
  """
  def conversation_example do
    # First message
    {:ok, ref} = SDK.start("What is Elixir?", to: self(), model: "haiku")

    session_id =
      receive do
        {:claude_complete, ^ref, sid} -> sid
      after
        30_000 -> raise "timeout"
      end

    IO.puts("Session ID: #{session_id}")

    # Follow-up message
    {:ok, ref2} = SDK.resume(session_id, "Give me a code example", to: self())

    receive do
      {:claude_complete, ^ref2, _sid} -> :ok
    after
      30_000 -> raise "timeout"
    end

    {:ok, session_id}
  end

  @doc """
  Background agent that processes tool uses.

  Shows how to handle different message types including tool uses.
  """
  def background_agent(prompt, opts \\ []) do
    {:ok, ref} = SDK.start(prompt, Keyword.put(opts, :to, self()))

    process_messages(ref)
  end

  defp process_messages(ref) do
    receive do
      {:claude_message, ^ref, %Message{type: :text, content: text}} ->
        IO.write(text)
        process_messages(ref)

      {:claude_message, ^ref, %Message{type: :tool_use, content: %{name: name}}} ->
        IO.puts("\n[Tool: #{name}]")
        process_messages(ref)

      {:claude_message, ^ref, %Message{type: :thinking, content: thinking}} ->
        IO.puts("\n[Thinking: #{String.slice(thinking, 0, 50)}...]")
        process_messages(ref)

      {:claude_message, ^ref, %Message{type: :usage, content: usage}} ->
        IO.puts("\n[Usage: #{inspect(usage)}]")
        process_messages(ref)

      {:claude_complete, ^ref, session_id} ->
        IO.puts("\n\nDone: #{session_id}")
        {:ok, session_id}

      {:claude_error, ^ref, reason} ->
        IO.puts("\n\nError: #{inspect(reason)}")
        {:error, reason}
    after
      300_000 -> {:error, :timeout}
    end
  end

  @doc """
  GenServer example that wraps SDK for stateful sessions.

  Shows how to build session management on top of the SDK.
  """
  defmodule SessionServer do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def send_message(pid, prompt) do
      GenServer.call(pid, {:send, prompt}, 120_000)
    end

    def get_session_id(pid) do
      GenServer.call(pid, :get_session_id)
    end

    @impl true
    def init(opts) do
      {:ok, %{session_id: nil, current_ref: nil, opts: opts}}
    end

    @impl true
    def handle_call({:send, prompt}, from, state) do
      ref =
        if state.session_id do
          {:ok, ref} = SDK.resume(state.session_id, prompt, to: self())
          ref
        else
          {:ok, ref} = SDK.start(prompt, Keyword.put(state.opts, :to, self()))
          ref
        end

      {:noreply, %{state | current_ref: ref}, {:continue, {:await_response, from, []}}}
    end

    @impl true
    def handle_call(:get_session_id, _from, state) do
      {:reply, state.session_id, state}
    end

    @impl true
    def handle_continue({:await_response, from, acc}, state) do
      receive do
        {:claude_message, ref, %Message{type: :text, content: text}} when ref == state.current_ref ->
          {:noreply, state, {:continue, {:await_response, from, [text | acc]}}}

        {:claude_complete, ref, session_id} when ref == state.current_ref ->
          response = acc |> Enum.reverse() |> Enum.join()
          GenServer.reply(from, {:ok, response})
          {:noreply, %{state | session_id: session_id, current_ref: nil}}

        {:claude_error, ref, reason} when ref == state.current_ref ->
          GenServer.reply(from, {:error, reason})
          {:noreply, %{state | current_ref: nil}}
      after
        120_000 ->
          GenServer.reply(from, {:error, :timeout})
          {:noreply, %{state | current_ref: nil}}
      end
    end
  end
end
