defmodule EyeInTheSky.IAM.BuiltinMatcher.RegistryTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.BuiltinMatcher.Registry

  test "has all seeded keys" do
    expected = ~w(
      block_sudo block_rm_rf protect_env_vars block_env_files
      block_read_outside_cwd block_push_master block_curl_pipe_sh
      block_work_on_main warn_destructive_sql
    )

    for key <- expected do
      assert Registry.known?(key), "missing registry key: #{key}"
      assert {:ok, module} = Registry.fetch(key)
      assert Code.ensure_loaded?(module)
      assert function_exported?(module, :matches?, 2)
    end
  end

  test "unknown keys return :error" do
    refute Registry.known?("nope")
    assert Registry.fetch("nope") == :error
  end
end
