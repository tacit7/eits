defmodule EyeInTheSky.Workers.SpeakWorker do
  @moduledoc "Background TTS via macOS `say`. Fire-and-forget; frees the MCP caller immediately."

  use Oban.Worker, queue: :jobs, max_attempts: 2

  @valid_voices ~w(Ava Isha Lee Jamie Serena)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message" => message} = args}) do
    voice = validated_voice(args["voice"])
    rate = validated_rate(args["rate"])

    case System.cmd("say", ["-v", "#{voice} (Premium)", "-r", to_string(rate), message],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {_, _} ->
        # Premium variant unavailable — fall back to standard voice
        case System.cmd("say", ["-v", voice, "-r", to_string(rate), message],
               stderr_to_stdout: true
             ) do
          {_, 0} -> :ok
          {output, code} -> {:error, "TTS failed (exit #{code}): #{String.trim(output)}"}
        end
    end
  end

  defp validated_voice(v) when v in @valid_voices, do: v
  defp validated_voice(_), do: EyeInTheSky.Settings.get("tts_voice") || "Ava"

  defp validated_rate(r) when is_integer(r) and r >= 90 and r <= 450, do: r
  defp validated_rate(_), do: EyeInTheSky.Settings.get_integer("tts_rate") || 200
end
