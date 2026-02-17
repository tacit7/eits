defmodule EyeInTheSkyWeb.MCP.Tools.Speak do
  @moduledoc "Speak a message aloud using macOS text-to-speech with premium voices"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @valid_voices ~w(Ava Isha Lee Jamie Serena)
  @default_voice "Ava"
  @default_rate 200

  schema do
    field :message, :string, required: true, description: "Message to speak aloud"

    field :voice, :string,
      description: "Premium voice to use (Ava, Isha, Lee, Jamie, Serena). Defaults to Ava"

    field :rate, :integer,
      description: "Speaking rate in words per minute (90-450). Defaults to 200"
  end

  @impl true
  def execute(params, frame) do
    message = params["message"]
    voice = validate_voice(params["voice"])
    rate = validate_rate(params["rate"])

    # Use premium voice variant
    voice_arg = "#{voice} (Premium)"

    case System.cmd("say", ["-v", voice_arg, "-r", to_string(rate), message],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        result = %{success: true, message: "Spoken aloud", voice_used: voice}
        response = Response.tool() |> Response.json(result)
        {:reply, response, frame}

      {output, _} ->
        # Fall back to non-premium voice
        case System.cmd("say", ["-v", voice, "-r", to_string(rate), message],
               stderr_to_stdout: true
             ) do
          {_, 0} ->
            result = %{success: true, message: "Spoken aloud (standard voice)", voice_used: voice}
            response = Response.tool() |> Response.json(result)
            {:reply, response, frame}

          {err, _} ->
            result = %{success: false, message: "TTS failed: #{output || err}"}
            response = Response.tool() |> Response.json(result)
            {:reply, response, frame}
        end
    end
  end

  defp validate_voice(nil), do: @default_voice
  defp validate_voice(v) when v in @valid_voices, do: v
  defp validate_voice(_), do: @default_voice

  defp validate_rate(nil), do: @default_rate
  defp validate_rate(r) when is_integer(r) and r >= 90 and r <= 450, do: r
  defp validate_rate(_), do: @default_rate
end
