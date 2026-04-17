defmodule EyeInTheSky.IAM.Seeds do
  @moduledoc """
  Seed definitions for built-in IAM system policies.

  Each entry carries a stable `system_key` used by
  `EyeInTheSky.IAM.seed_builtin/1` for idempotent upserts. Matcher fields
  (`agent_type`, `action`, `project_*`, `resource_glob`, `builtin_matcher`)
  are locked on system policies — `editable_fields` lists the operator-
  tunable knobs (`enabled`, `priority`, `condition`, `message`).

  `run/0` is safe to call on every boot; existing rows are not modified.
  """

  require Logger

  alias EyeInTheSky.IAM

  @editable ~w(enabled priority condition message)

  @policies [
    %{
      system_key: "block_sudo",
      name: "Block privilege escalation",
      effect: "deny",
      action: "Bash",
      builtin_matcher: "block_sudo",
      priority: 100,
      message: "Privilege escalation (sudo/doas/pkexec/runas) is blocked."
    },
    %{
      system_key: "block_rm_rf",
      name: "Block rm -rf against dangerous paths",
      effect: "deny",
      action: "Bash",
      builtin_matcher: "block_rm_rf",
      priority: 100,
      message: "rm -rf targeting system or home paths is blocked."
    },
    %{
      system_key: "protect_env_vars",
      name: "Protect sensitive environment variables",
      effect: "deny",
      action: "Bash",
      builtin_matcher: "protect_env_vars",
      priority: 90,
      message: "Dumping or reading sensitive env vars is blocked."
    },
    %{
      system_key: "block_env_files",
      name: "Block access to .env files",
      effect: "deny",
      action: "*",
      builtin_matcher: "block_env_files",
      priority: 90,
      message: "Access to .env files is blocked. Use .env.example for templates."
    },
    %{
      system_key: "block_read_outside_cwd",
      name: "Block reads outside project cwd",
      effect: "deny",
      action: "*",
      builtin_matcher: "block_read_outside_cwd",
      priority: 80,
      message: "Reading paths outside the project cwd is blocked."
    },
    %{
      system_key: "block_push_master",
      name: "Block git push to protected branches",
      effect: "deny",
      action: "Bash",
      builtin_matcher: "block_push_master",
      priority: 95,
      message: "Pushing to a protected branch is blocked.",
      condition: %{"protectedBranches" => ["main", "master"]}
    },
    %{
      system_key: "block_curl_pipe_sh",
      name: "Block curl|sh remote execution",
      effect: "deny",
      action: "Bash",
      builtin_matcher: "block_curl_pipe_sh",
      priority: 100,
      message: "curl/wget piped to a shell is blocked; download and inspect first."
    },
    %{
      system_key: "block_work_on_main",
      name: "Block mutating git ops on protected branches",
      effect: "deny",
      action: "Bash",
      builtin_matcher: "block_work_on_main",
      priority: 95,
      message: "Mutating git operations on a protected branch are blocked; use a worktree.",
      condition: %{"protectedBranches" => ["main", "master"]}
    },
    %{
      system_key: "warn_destructive_sql",
      name: "Warn on destructive SQL",
      effect: "instruct",
      action: "Bash",
      builtin_matcher: "warn_destructive_sql",
      priority: 50,
      message:
        "Destructive SQL detected (DROP/TRUNCATE/DELETE without WHERE). Confirm intent and take a backup first."
    }
  ]

  @doc "Seed or upsert all built-in system policies. Safe to call on every boot."
  @spec run() :: :ok
  def run do
    Enum.each(@policies, fn attrs ->
      attrs_with_editable = Map.put(attrs, :editable_fields, @editable)

      case IAM.seed_builtin(attrs_with_editable) do
        {:ok, _policy} ->
          :ok

        {:error, changeset} ->
          Logger.error(
            "IAM built-in seed failed",
            system_key: attrs[:system_key],
            errors: inspect(changeset.errors)
          )
      end
    end)

    :ok
  end

  @doc "Return the seed specs (for introspection, tests, diagnostics)."
  @spec policies() :: [map()]
  def policies, do: @policies
end
