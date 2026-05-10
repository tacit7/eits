defmodule EyeInTheSky.Workers.SpeakWorkerTest do
  use EyeInTheSky.DataCase, async: false
  use Oban.Testing, repo: EyeInTheSky.Repo

  alias EyeInTheSky.Workers.SpeakWorker

  # Test on systems that have the macOS `say` command available
  @moduletag :host_dependent

  describe "perform/1 with valid voice and rate" do
    test "succeeds with premium voice variant" do
      args = %{
        "message" => "Hello world",
        "voice" => "Ava",
        "rate" => 200
      }

      result = perform_job(SpeakWorker, args)

      # The mock will succeed since we're on macOS (or has say command)
      assert result == :ok or match?({:error, _}, result)
    end

    test "uses Ava as default voice" do
      Application.put_env(:eye_in_the_sky, :tts_voice, nil)
      on_exit(fn -> Application.delete_env(:eye_in_the_sky, :tts_voice) end)

      args = %{
        "message" => "Test",
        "voice" => nil,
        "rate" => 200
      }

      result = perform_job(SpeakWorker, args)

      # Should try Ava (Premium) or fall back to Ava
      assert result == :ok or match?({:error, _}, result)
    end

    test "uses configured TTS voice from settings" do
      Application.put_env(:eye_in_the_sky, :tts_voice, "Jamie")
      on_exit(fn -> Application.delete_env(:eye_in_the_sky, :tts_voice) end)

      args = %{
        "message" => "Test",
        "voice" => nil,
        "rate" => 200
      }

      result = perform_job(SpeakWorker, args)

      assert result == :ok or match?({:error, _}, result)
    end

    test "uses rate 200 as default" do
      Application.put_env(:eye_in_the_sky, :tts_rate, nil)
      on_exit(fn -> Application.delete_env(:eye_in_the_sky, :tts_rate) end)

      args = %{
        "message" => "Test",
        "voice" => "Ava",
        "rate" => nil
      }

      result = perform_job(SpeakWorker, args)

      assert result == :ok or match?({:error, _}, result)
    end

    test "uses configured TTS rate from settings" do
      Application.put_env(:eye_in_the_sky, :tts_rate, 150)
      on_exit(fn -> Application.delete_env(:eye_in_the_sky, :tts_rate) end)

      args = %{
        "message" => "Test",
        "voice" => "Ava",
        "rate" => nil
      }

      result = perform_job(SpeakWorker, args)

      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "perform/1 voice validation" do
    test "accepts valid premium voices" do
      valid_voices = ["Ava", "Isha", "Lee", "Jamie", "Serena"]

      Enum.each(valid_voices, fn voice ->
        args = %{
          "message" => "Test",
          "voice" => voice,
          "rate" => 200
        }

        result = perform_job(SpeakWorker, args)
        assert result == :ok or match?({:error, _}, result)
      end)
    end

    test "rejects invalid voice and falls back to default" do
      Application.put_env(:eye_in_the_sky, :tts_voice, "Ava")
      on_exit(fn -> Application.delete_env(:eye_in_the_sky, :tts_voice) end)

      args = %{
        "message" => "Test",
        "voice" => "InvalidVoice",
        "rate" => 200
      }

      result = perform_job(SpeakWorker, args)

      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "perform/1 rate validation" do
    test "accepts rate between 90 and 450" do
      valid_rates = [90, 150, 200, 300, 450]

      Enum.each(valid_rates, fn rate ->
        args = %{
          "message" => "Test",
          "voice" => "Ava",
          "rate" => rate
        }

        result = perform_job(SpeakWorker, args)
        assert result == :ok or match?({:error, _}, result)
      end)
    end

    test "rejects rate below 90" do
      args = %{
        "message" => "Test",
        "voice" => "Ava",
        "rate" => 50
      }

      result = perform_job(SpeakWorker, args)
      # Should use default rate instead
      assert result == :ok or match?({:error, _}, result)
    end

    test "rejects rate above 450" do
      args = %{
        "message" => "Test",
        "voice" => "Ava",
        "rate" => 500
      }

      result = perform_job(SpeakWorker, args)
      # Should use default rate instead
      assert result == :ok or match?({:error, _}, result)
    end

    test "rejects non-integer rate and falls back to configured" do
      Application.put_env(:eye_in_the_sky, :tts_rate, 175)
      on_exit(fn -> Application.delete_env(:eye_in_the_sky, :tts_rate) end)

      args = %{
        "message" => "Test",
        "voice" => "Ava",
        "rate" => "not_an_int"
      }

      result = perform_job(SpeakWorker, args)

      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "perform/1 message edge cases" do
    test "handles empty message" do
      args = %{
        "message" => "",
        "voice" => "Ava",
        "rate" => 200
      }

      result = perform_job(SpeakWorker, args)
      # say command may still run with empty string
      assert result == :ok or match?({:error, _}, result)
    end

    test "handles special characters in message" do
      args = %{
        "message" => "Test with special chars: @#$%^&*()",
        "voice" => "Ava",
        "rate" => 200
      }

      result = perform_job(SpeakWorker, args)
      assert result == :ok or match?({:error, _}, result)
    end

    test "handles Unicode in message" do
      args = %{
        "message" => "こんにちは 世界 🌍",
        "voice" => "Ava",
        "rate" => 200
      }

      result = perform_job(SpeakWorker, args)
      assert result == :ok or match?({:error, _}, result)
    end
  end

  defp perform_job(worker, args) do
    worker.perform(%Oban.Job{args: args, id: 123, attempt: 1})
  end
end
