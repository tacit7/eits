# Task 14 resume-semantics validation driver.
# Usage: EITS_PI_SESSION_ROOT=<tmp> mix run validate_resume.exs <case>
# Cases: success | cancel | crash | repeated
# Drives Pi.SDK directly with the real harness + real provider (anthropic haiku).

defmodule ResumeValidation do
  @model "anthropic/claude-haiku-4-5"

  def run_turn(session_uuid, prompt, opts \\ []) do
    {:ok, ref, _pid} =
      EyeInTheSky.Pi.SDK.start(prompt,
        to: self(),
        session_id: session_uuid,
        model: @model,
        project_path: System.tmp_dir!()
      )

    if kill_after = opts[:kill_after_ms] do
      spawn(fn ->
        Process.sleep(kill_after)
        case EyeInTheSky.Claude.SDK.Registry.lookup(ref) do
          port when is_port(port) ->
            case Port.info(port, :os_pid) do
              {:os_pid, pid} -> System.cmd("kill", ["-9", to_string(pid)])
              _ -> :ok
            end
          _ -> :ok
        end
      end)
    end

    if cancel_after = opts[:cancel_after_ms] do
      spawn(fn ->
        Process.sleep(cancel_after)
        EyeInTheSky.Pi.SDK.cancel(ref)
      end)
    end

    collect(ref, [], nil)
  end

  defp collect(ref, texts, _outcome) do
    receive do
      {:claude_message, ^ref, %{type: :text, content: c}} -> collect(ref, [c | texts], nil)
      {:claude_message, ^ref, _} -> collect(ref, texts, nil)
      {:claude_complete, ^ref, sid} -> {:complete, sid, texts |> Enum.reverse() |> Enum.join()}
      {:claude_error, ^ref, reason} -> {:error, reason, texts |> Enum.reverse() |> Enum.join()}
    after
      120_000 -> {:timeout, nil, texts |> Enum.reverse() |> Enum.join()}
    end
  end

  def transcript_listing(session_uuid) do
    dir = Path.join(EyeInTheSky.Pi.session_root(), session_uuid)
    case File.ls(dir) do
      {:ok, files} -> "#{dir}: #{inspect(files)}"
      {:error, e} -> "#{dir}: #{inspect(e)}"
    end
  end

  def check_recall(uuid, label) do
    r2 = run_turn(uuid, "What word did I ask you to remember? Answer with just the word.")
    IO.puts("#{label} turn2: #{inspect(elem(r2, 0))} text=#{inspect(elem(r2, 2))}")
    recalled = elem(r2, 2) =~ ~r/flamingo/i
    IO.puts("#{label} RECALL: #{if recalled, do: "PASS", else: "FAIL"}")
    IO.puts("#{label} dir: #{transcript_listing(uuid)}")
  end
end

uuid = "task14-" <> (System.get_env("CASE_ID") || Ecto.UUID.generate())

case System.argv() do
  ["success"] ->
    r1 = ResumeValidation.run_turn(uuid, "Remember the word FLAMINGO. Just say OK.")
    IO.puts("success turn1: #{inspect(elem(r1, 0))}")
    ResumeValidation.check_recall(uuid, "success")

  ["cancel"] ->
    r1 = ResumeValidation.run_turn(uuid, "Count slowly from 1 to 50, one number per line. But first remember the word FLAMINGO.", cancel_after_ms: 4_000)
    IO.puts("cancel turn1: #{inspect(elem(r1, 0))} reason=#{inspect(elem(r1, 1))}")
    r2 = ResumeValidation.run_turn(uuid, "Say OK.")
    IO.puts("cancel turn2 (clean start after cancel): #{inspect(elem(r2, 0))}")
    IO.puts("cancel dir: #{ResumeValidation.transcript_listing(uuid)}")

  ["crash"] ->
    r1 = ResumeValidation.run_turn(uuid, "Count slowly from 1 to 50, one number per line.", kill_after_ms: 4_000)
    IO.puts("crash turn1: #{inspect(elem(r1, 0))} reason=#{inspect(elem(r1, 1))}")
    r2 = ResumeValidation.run_turn(uuid, "Say OK.")
    IO.puts("crash turn2 (clean start after kill -9): #{inspect(elem(r2, 0))}")
    IO.puts("crash dir: #{ResumeValidation.transcript_listing(uuid)}")

  ["repeated"] ->
    r1 = ResumeValidation.run_turn(uuid, "Remember the word FLAMINGO. Just say OK.")
    IO.puts("repeated turn1: #{inspect(elem(r1, 0))}")
    r2 = ResumeValidation.run_turn(uuid, "Also remember the word OSTRICH. Just say OK.")
    IO.puts("repeated turn2: #{inspect(elem(r2, 0))}")
    r3 = ResumeValidation.run_turn(uuid, "What TWO words did I ask you to remember? Just the words.")
    both = elem(r3, 2) =~ ~r/flamingo/i and elem(r3, 2) =~ ~r/ostrich/i
    IO.puts("repeated turn3: #{inspect(elem(r3, 0))} text=#{inspect(elem(r3, 2))}")
    IO.puts("repeated RECALL BOTH: #{if both, do: "PASS", else: "FAIL"}")
    IO.puts("repeated dir: #{ResumeValidation.transcript_listing(uuid)}")

  other ->
    IO.puts("unknown case #{inspect(other)}")
end
