defmodule Mix.Tasks.Eits.RegisterTest do
  use EyeInTheSky.DataCase

  alias EyeInTheSky.Accounts.RegistrationToken

  # Mix.Shell.Process captures shell output as messages to this process.
  # Restore the real shell on exit so other tests are not affected.
  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  # Collect N shell messages; returns the list of message strings.
  defp drain_shell_messages(count) do
    for _ <- 1..count do
      receive do
        {:mix_shell, :info, [msg]} -> msg
        {:mix_shell, :error, [msg]} -> msg
      after
        500 -> ""
      end
    end
  end

  describe "run/1 — happy path" do
    test "prints registration URL containing the raw token" do
      Mix.Tasks.Eits.Register.run(["alice"])

      messages = drain_shell_messages(3)
      full = Enum.join(messages, "\n")

      assert full =~ "alice"
      assert full =~ "/auth/register?token="
    end

    test "URL contains the configured wax_ origin" do
      origin = Application.get_env(:wax_, :origin, "https://localhost:5001")
      Mix.Tasks.Eits.Register.run(["bob"])

      messages = drain_shell_messages(3)
      url_line = Enum.find(messages, &String.contains?(&1, "/auth/register?token="))

      assert url_line =~ origin
    end

    test "URL includes the username" do
      Mix.Tasks.Eits.Register.run(["carol"])

      messages = drain_shell_messages(3)
      full = Enum.join(messages, "\n")

      assert full =~ "carol"
    end

    test "prints expiry reminder" do
      Mix.Tasks.Eits.Register.run(["dave"])

      messages = drain_shell_messages(3)
      full = Enum.join(messages, "\n")

      assert full =~ "15 minutes"
    end

    test "persists a RegistrationToken to the database with the correct username" do
      Mix.Tasks.Eits.Register.run(["eve"])

      drain_shell_messages(3)

      rt = Repo.one!(RegistrationToken)

      assert rt.username == "eve"
      assert is_binary(rt.token)
      # Token is stored as an HMAC hash — not the raw value printed to stdout.
      assert byte_size(rt.token) > 0
      assert rt.expires_at != nil
    end

    test "token in URL differs from hashed token stored in DB" do
      Mix.Tasks.Eits.Register.run(["frank"])

      messages = drain_shell_messages(3)
      url_line = Enum.find(messages, &String.contains?(&1, "/auth/register?token="))
      raw_token = url_line |> String.split("token=") |> List.last() |> String.trim()

      rt = Repo.one!(RegistrationToken)

      # DB stores a hashed form; raw token from output must differ.
      refute rt.token == raw_token
    end
  end

  describe "run/1 — wrong arity" do
    test "prints usage error when no arguments are given" do
      Mix.Tasks.Eits.Register.run([])

      assert_receive {:mix_shell, :error, [message]}
      assert message =~ "Usage"
      assert message =~ "eits.register"
    end

    test "prints usage error when more than one argument is given" do
      Mix.Tasks.Eits.Register.run(["alice", "extra"])

      assert_receive {:mix_shell, :error, [message]}
      assert message =~ "Usage"
    end

    test "does not create any DB record when arity is wrong" do
      Mix.Tasks.Eits.Register.run([])

      drain_shell_messages(1)

      count =
        Repo.query!("SELECT COUNT(*) FROM registration_tokens", []).rows
        |> hd()
        |> hd()

      assert count == 0
    end
  end
end
