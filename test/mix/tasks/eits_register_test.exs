defmodule Mix.Tasks.Eits.RegisterTest do
  use EyeInTheSky.DataCase

  # Mix.Shell.Process captures shell output as messages to this process.
  # Restore the real shell on exit so other tests are not affected.
  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "run/1 — happy path" do
    test "prints registration URL containing the raw token" do
      Mix.Tasks.Eits.Register.run(["alice"])

      assert_receive {:mix_shell, :info, [line1]}
      assert_receive {:mix_shell, :info, [line2]}
      assert_receive {:mix_shell, :info, [line3]}

      full_output = [line1, line2, line3] |> Enum.join("\n")

      assert full_output =~ "alice"
      assert full_output =~ "/auth/register?token="
    end

    test "URL contains the configured wax_ origin" do
      origin = Application.get_env(:wax_, :origin, "https://localhost:5001")
      Mix.Tasks.Eits.Register.run(["bob"])

      messages =
        for _ <- 1..3 do
          receive do
            {:mix_shell, :info, [msg]} -> msg
          after
            500 -> ""
          end
        end

      assert Enum.any?(messages, &String.starts_with?(&1, "  #{origin}"))
    end

    test "URL includes username in the registration link output" do
      Mix.Tasks.Eits.Register.run(["carol"])

      messages =
        for _ <- 1..3 do
          receive do
            {:mix_shell, :info, [msg]} -> msg
          after
            500 -> ""
          end
        end

      assert Enum.any?(messages, &(&1 =~ "carol"))
    end

    test "prints expiry reminder" do
      Mix.Tasks.Eits.Register.run(["dave"])

      messages =
        for _ <- 1..3 do
          receive do
            {:mix_shell, :info, [msg]} -> msg
          after
            500 -> ""
          end
        end

      assert Enum.any?(messages, &(&1 =~ "15 minutes"))
    end

    test "persists a RegistrationToken to the database" do
      Mix.Tasks.Eits.Register.run(["eve"])

      # Drain shell messages
      for _ <- 1..3, do: receive(do: ({:mix_shell, :info, _} -> :ok), after: (500 -> :ok))

      count =
        Repo.query!("SELECT COUNT(*) FROM registration_tokens", []).rows
        |> hd()
        |> hd()

      assert count == 1
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
  end
end
