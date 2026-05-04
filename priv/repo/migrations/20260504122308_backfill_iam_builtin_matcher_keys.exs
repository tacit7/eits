defmodule EyeInTheSky.Repo.Migrations.BackfillIamBuiltinMatcherKeys do
  @moduledoc """
  Backfill `iam_policies.builtin_matcher` for legacy system rows seeded
  before the matcher key was wired up.

  When `builtin_matcher` is NULL, the evaluator falls into the declarative
  match path (resource_glob + condition). For these rows that means
  `resource_glob = NULL` and `condition = {}` — which matches every context.
  Result: `block_env_files` (deny, action=*) blocked every file read,
  `block_sudo` (deny, Bash) blocked every Bash call, etc.

  For each affected `system_key`, the matcher module key happens to equal
  the `system_key` itself, so we backfill in one statement.

  `seed_builtin/1` has seed-once semantics (existing rows are not updated),
  so this fix has to ship as a migration.
  """

  use Ecto.Migration

  @legacy_keys ~w(
    block_sudo
    block_rm_rf
    block_curl_pipe_sh
    protect_env_vars
    block_env_files
    block_read_outside_cwd
    warn_destructive_sql
  )

  def up do
    keys_csv = Enum.map_join(@legacy_keys, ",", &"'#{&1}'")

    execute("""
    UPDATE iam_policies
    SET builtin_matcher = system_key
    WHERE builtin_matcher IS NULL
      AND system_key IN (#{keys_csv})
    """)
  end

  def down do
    keys_csv = Enum.map_join(@legacy_keys, ",", &"'#{&1}'")

    execute("""
    UPDATE iam_policies
    SET builtin_matcher = NULL
    WHERE system_key IN (#{keys_csv})
    """)
  end
end
