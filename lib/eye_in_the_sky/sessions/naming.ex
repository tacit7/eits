defmodule EyeInTheSky.Sessions.Naming do
  @moduledoc false

  require Logger

  import Ecto.Query
  alias EyeInTheSky.{Events, Repo}
  alias EyeInTheSky.Claude.BinaryLocator
  alias EyeInTheSky.Sessions.Session

  @model "claude-haiku-4-5-20251001"
  @max_prompt_chars 200
  @max_name_chars 60
  @timeout_ms 15_000

  @prompt_template "Output ONLY a short descriptive name for this chat session " <>
                     "(3–6 words, noun-preferring, no quotes, no markdown, no trailing punctuation). " <>
                     "Nothing else — just the name on a single line.\n\n" <>
                     "Opening message:\n\n"

  @doc """
  Non-fatal auto-name. Only writes if the session name still equals `fallback_name` —
  the DB WHERE clause makes the guard atomic (no TOCTOU).
  """
  def try_auto_name(session_id, body, fallback_name) do
    with {:ok, generated_name} <- generate_name(body),
         {1, [updated_session]} <-
           Repo.update_all(
             from(s in Session,
               where:
                 s.id == ^session_id and
                   ((is_nil(^fallback_name) and is_nil(s.name)) or
                    (not is_nil(^fallback_name) and s.name == ^fallback_name)),
               select: s
             ),
             set: [name: generated_name]
           ) do
      Events.broadcast_rail_session_updated(updated_session)
    else
      {:error, :no_binary} ->
        Logger.debug("auto-naming skipped for session #{session_id}: claude binary not found")
        :ok

      _ ->
        :ok
    end
  end

  @doc "Returns `{:ok, name}` or `{:error, reason}`. Never raises."
  def generate_name(body) do
    case BinaryLocator.find() do
      {:error, reason} ->
        Logger.debug("auto-naming: claude binary not found: #{inspect(reason)}")
        {:error, :no_binary}

      {:ok, claude_bin} ->
        prompt = @prompt_template <> String.slice(body, 0, @max_prompt_chars)

        task =
          Task.async(fn ->
            System.cmd(
              claude_bin,
              ["-p", prompt, "--model", @model, "--no-session-persistence"],
              stderr_to_stdout: false,
              env: [{"EITS_WORKFLOW", "0"}]
            )
          end)

        case Task.yield(task, @timeout_ms) || Task.shutdown(task) do
          {:ok, {output, 0}} ->
            name =
              output
              |> String.trim()
              |> String.trim("\"")
              |> String.trim("'")
              |> String.slice(0, @max_name_chars)

            if name == "", do: {:error, :empty_name}, else: {:ok, name}

          {:ok, {error_output, exit_code}} ->
            Logger.warning(
              "auto-naming CLI failed: exit=#{exit_code} output=#{inspect(String.slice(error_output, 0, 200))}"
            )

            {:error, {:cli_error, exit_code}}

          nil ->
            Logger.warning("auto-naming timed out after #{@timeout_ms}ms")
            {:error, :timeout}
        end
    end
  end
end
