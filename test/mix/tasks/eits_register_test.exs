defmodule Mix.Tasks.Eits.RegisterTest do
  use EyeInTheSky.DataCase

  alias EyeInTheSky.Accounts.RegistrationToken
  alias EyeInTheSky.Repo

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "run/1 with a single username argument" do
    test "inserts a registration token row into the database" do
      Mix.Tasks.Eits.Register.run(["alice"])

      assert Repo.aggregate(RegistrationToken, :count, :id) == 1
    end

    test "stores a hashed token, not the raw token" do
      Mix.Tasks.Eits.Register.run(["alice"])

      assert_receive {:mix_shell, :info, [output]}

      raw_token =
        output
        |> String.split("\n")
        |> Enum.find_value(fn line ->
          case Regex.run(~r/token=(\S+)/, line) do
            [_, token] -> token
            _ -> nil
          end
        end)

      refute is_nil(raw_token), "expected raw token in output"

      rt = Repo.one!(RegistrationToken)
      refute rt.token == raw_token
    end

    test "prints a URL containing the raw token" do
      Mix.Tasks.Eits.Register.run(["bob"])

      assert_receive {:mix_shell, :info, [output]}
      assert output =~ "bob"
      assert output =~ "token="
      assert output =~ "register"
    end

    test "prints expiry notice" do
      Mix.Tasks.Eits.Register.run(["charlie"])

      assert_receive {:mix_shell, :info, [_first]}
      assert_receive {:mix_shell, :info, [_url]}
      assert_receive {:mix_shell, :info, [expiry_line]}
      assert expiry_line =~ "15 minutes"
    end

    test "stores the correct username on the token" do
      Mix.Tasks.Eits.Register.run(["diana"])

      rt = Repo.one!(RegistrationToken)
      assert rt.username == "diana"
    end

    test "token expires approximately 15 minutes from now" do
      Mix.Tasks.Eits.Register.run(["eve"])

      rt = Repo.one!(RegistrationToken)
      diff = NaiveDateTime.diff(rt.expires_at, NaiveDateTime.utc_now(), :second)
      # Should be within 1 second of 15 minutes (900 seconds)
      assert diff >= 899 and diff <= 901
    end
  end

  describe "run/1 with wrong argument count" do
    test "prints usage error when no arguments given" do
      Mix.Tasks.Eits.Register.run([])

      assert_receive {:mix_shell, :error, [msg]}
      assert msg =~ "Usage:"
    end

    test "does not insert any DB row when no arguments given" do
      Mix.Tasks.Eits.Register.run([])

      assert Repo.aggregate(RegistrationToken, :count, :id) == 0
    end

    test "prints usage error when more than one argument given" do
      Mix.Tasks.Eits.Register.run(["alice", "extra"])

      assert_receive {:mix_shell, :error, [msg]}
      assert msg =~ "Usage:"
    end

    test "does not insert any DB row when more than one argument given" do
      Mix.Tasks.Eits.Register.run(["alice", "extra"])

      assert Repo.aggregate(RegistrationToken, :count, :id) == 0
    end
  end
end
