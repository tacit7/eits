defmodule EyeInTheSky.IAM.BuiltinMatcher.Registry do
  @moduledoc """
  Stable-key → module registry for built-in IAM matchers.

  Keys stored in `iam_policies.builtin_matcher` are validated against
  this registry at policy write time. Using a registry (rather than
  free-form `Module.concat/1` dispatch) gives us:

    * validation at the changeset layer
    * safer dispatch (unknown keys fail loudly, they don't resolve to
      attacker-controlled modules)
    * decoupling: the DB row carries a stable name that survives
      refactors
    * clean audit snapshots (the key, not a module name, is what you
      log)

  To add a new built-in:

    1. Implement the module conforming to `EyeInTheSky.IAM.BuiltinMatcher`.
    2. Add the key → module pair to `@matchers`.
    3. Seed a policy row with that `builtin_matcher` key.
  """

  alias EyeInTheSky.IAM.Builtin

  @matchers %{
    "block_sudo" => Builtin.BlockSudo,
    "block_rm_rf" => Builtin.BlockRmRf,
    "protect_env_vars" => Builtin.ProtectEnvVars,
    "block_env_files" => Builtin.BlockEnvFiles,
    "block_read_outside_cwd" => Builtin.BlockReadOutsideCwd,
    "block_push_master" => Builtin.BlockPushMaster,
    "block_curl_pipe_sh" => Builtin.BlockCurlPipeSh,
    "block_work_on_main" => Builtin.BlockWorkOnMain,
    "warn_destructive_sql" => Builtin.WarnDestructiveSql,
    "sanitize_api_keys" => Builtin.SanitizeApiKeys,
    "sanitize_prompt_api_keys" => Builtin.SanitizePromptApiKeys,
    "workflow_business_hours_only" => Builtin.WorkflowBusinessHoursOnly,
    "warn_git_amend" => Builtin.WarnGitAmend,
    "warn_all_files_staged" => Builtin.WarnAllFilesStaged,
    "block_force_push" => Builtin.BlockForcePush,
    "warn_git_stash_drop" => Builtin.WarnGitStashDrop,
    "warn_large_file_write" => Builtin.WarnLargeFileWrite,
    "sanitize_connection_strings" => Builtin.SanitizeConnectionStrings,
    "block_kubectl" => Builtin.BlockKubectl,
    "block_terraform" => Builtin.BlockTerraform,
    "block_aws_cli" => Builtin.BlockAwsCli,
    "block_gcloud" => Builtin.BlockGcloud,
    "block_az_cli" => Builtin.BlockAzCli,
    "block_helm" => Builtin.BlockHelm,
    "warn_schema_alteration" => Builtin.WarnSchemaAlteration,
    "warn_package_publish" => Builtin.WarnPackagePublish,
    "warn_global_package_install" => Builtin.WarnGlobalPackageInstall,
    "warn_background_process" => Builtin.WarnBackgroundProcess
  }

  @doc "Return all known registry keys."
  @spec keys() :: [String.t()]
  def keys, do: Map.keys(@matchers)

  @doc "Look up the module for a key."
  @spec fetch(String.t()) :: {:ok, module()} | :error
  def fetch(key) when is_binary(key), do: Map.fetch(@matchers, key)

  @doc "`true` when the key is registered."
  @spec known?(String.t()) :: boolean()
  def known?(key) when is_binary(key), do: Map.has_key?(@matchers, key)
end
