defmodule Mix.Tasks.Eits.Gen.ApiKeyTest do
  use EyeInTheSky.DataCase

  alias EyeInTheSky.Accounts.ApiKey
  alias EyeInTheSky.Repo

  # Use Mix.Shell.Process so shell output is captured as messages to this test
  # process rather than written to stdout. Restore the default shell on exit.
  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "run/1" do
    test "creates a key with the default label 'default'" do
      Mix.Tasks.Eits.Gen.ApiKey.run([])

      api_key = Repo.one!(ApiKey)
      assert api_key.label == "default"
      assert api_key.valid_until == nil
      assert is_binary(api_key.key_hash)
    end

    test "prints raw key and 'EITS API Key generated' on success" do
      Mix.Tasks.Eits.Gen.ApiKey.run([])

      assert_receive {:mix_shell, :info, [output]}
      assert output =~ "EITS API Key generated"
      assert output =~ "Label:   default"
      assert output =~ "Expires: never"
      # Raw key is 32 bytes base64-encoded — will be in the output
      assert output =~ "This is the only time the raw key will be shown"
    end

    test "creates a key with a custom label via --label" do
      Mix.Tasks.Eits.Gen.ApiKey.run(["--label", "ci"])

      api_key = Repo.one!(ApiKey)
      assert api_key.label == "ci"

      assert_receive {:mix_shell, :info, [output]}
      assert output =~ "Label:   ci"
    end

    test "creates a key with valid_until set via --valid-until" do
      Mix.Tasks.Eits.Gen.ApiKey.run(["--valid-until", "2030-01-01T00:00:00"])

      api_key = Repo.one!(ApiKey)
      assert api_key.valid_until == ~N[2030-01-01 00:00:00]

      assert_receive {:mix_shell, :info, [output]}
      assert output =~ "Expires: 2030-01-01T00:00:00"
    end

    test "raises Mix.Error on an invalid --valid-until format" do
      assert_raise Mix.Error, ~r/Invalid --valid-until format/, fn ->
        Mix.Tasks.Eits.Gen.ApiKey.run(["--valid-until", "bad-date"])
      end

      # No key should have been inserted
      assert Repo.aggregate(ApiKey, :count, :id) == 0
    end

    test "stores a hash, not the raw key" do
      Mix.Tasks.Eits.Gen.ApiKey.run([])

      api_key = Repo.one!(ApiKey)

      assert_receive {:mix_shell, :info, [output]}
      # Extract the printed raw key (the line between the two blank lines)
      [raw_key] =
        output
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&(byte_size(&1) > 20 and not String.contains?(&1, " ")))
        |> Enum.take(1)

      # The stored hash must differ from the raw key
      refute api_key.key_hash == raw_key
      # But hashing the raw key must reproduce the stored hash
      assert ApiKey.hash_token(raw_key) == api_key.key_hash
    end
  end
end
