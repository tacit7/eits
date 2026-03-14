defmodule EyeInTheSkyWeb.MCP.Tools.Speak do
  @moduledoc "Speak a message aloud using macOS text-to-speech with premium voices"

  use Anubis.Server.Component, type: :tool

  alias EyeInTheSkyWeb.MCP.Tools.ResponseHelper

  @valid_voices ~w(Ava Isha Lee Jamie Serena)

  schema do
    field :message, :string, required: true, description: "Message to speak aloud"

    field :voice, :string,
      description: "Premium voice to use (Ava, Isha, Lee, Jamie, Serena). Defaults to Ava"

    field :rate, :integer,
      description: "Speaking rate in words per minute (90-450). Defaults to 200"
  end

  @impl true
  def execute(params, frame) do
    message = params[:message]
    voice = validate_voice(params[:voice])
    rate = validate_rate(params[:rate])

    result =
      %{"message" => message, "voice" => voice, "rate" => rate}
      |> EyeInTheSkyWeb.Workers.SpeakWorker.new()
      |> Oban.insert()
      |> case do
        {:ok, _job} -> %{success: true, message: "Queued for TTS", voice_used: voice}
        {:error, reason} -> %{success: false, message: "Failed to queue TTS: #{inspect(reason)}"}
      end

    response = ResponseHelper.json_response(result)
    {:reply, response, frame}
  end

  defp validate_voice(nil), do: EyeInTheSkyWeb.Settings.get("tts_voice") || "Ava"
  defp validate_voice(v) when v in @valid_voices, do: v
  defp validate_voice(_), do: EyeInTheSkyWeb.Settings.get("tts_voice") || "Ava"

  defp validate_rate(nil) do
    EyeInTheSkyWeb.Settings.get_integer("tts_rate") || 200
  end

  defp validate_rate(r) when is_integer(r) and r >= 90 and r <= 450, do: r

  defp validate_rate(_) do
    EyeInTheSkyWeb.Settings.get_integer("tts_rate") || 200
  end
end
