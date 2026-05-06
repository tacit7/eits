defmodule EyeInTheSky.IAM.Builtin.PreferPackageManagerTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.PreferPackageManager
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}
  defp policy(cond \\ nil), do: %Policy{condition: cond}
  defp policy_for(manager), do: policy(%{"packageManager" => manager})

  test "matches when npm is used but pnpm is preferred" do
    assert PreferPackageManager.matches?(policy_for("pnpm"), ctx("npm install lodash"))
  end

  test "matches when yarn is used but npm is preferred" do
    assert PreferPackageManager.matches?(policy_for("npm"), ctx("yarn add react"))
  end

  test "matches when pnpm is used but yarn is preferred" do
    assert PreferPackageManager.matches?(policy_for("yarn"), ctx("pnpm install"))
  end

  test "matches when bun is used but npm is preferred" do
    assert PreferPackageManager.matches?(policy_for("npm"), ctx("bun install"))
  end

  test "matches when npm is used but bun is preferred (run subcommand)" do
    assert PreferPackageManager.matches?(policy_for("bun"), ctx("npm run build"))
  end

  test "matches npx when pnpm is preferred" do
    assert PreferPackageManager.matches?(policy_for("pnpm"), ctx("npx create-react-app my-app"))
  end

  test "matches bunx when npm is preferred" do
    assert PreferPackageManager.matches?(policy_for("npm"), ctx("bunx eslint ."))
  end

  test "matches yarn remove when npm is preferred" do
    assert PreferPackageManager.matches?(policy_for("npm"), ctx("yarn remove lodash"))
  end

  test "does not match when the correct manager is used (pnpm)" do
    refute PreferPackageManager.matches?(policy_for("pnpm"), ctx("pnpm install"))
  end

  test "does not match when the correct manager is used (npm install)" do
    refute PreferPackageManager.matches?(policy_for("npm"), ctx("npm install lodash"))
  end

  test "does not match when the correct manager is used (yarn add)" do
    refute PreferPackageManager.matches?(policy_for("yarn"), ctx("yarn add react"))
  end

  test "does not match when the correct manager is used (bun run)" do
    refute PreferPackageManager.matches?(policy_for("bun"), ctx("bun run test"))
  end

  test "does not match when no packageManager condition is set" do
    refute PreferPackageManager.matches?(policy(), ctx("npm install lodash"))
  end

  test "does not match when condition map lacks packageManager key" do
    refute PreferPackageManager.matches?(policy(%{"other" => "value"}), ctx("yarn add react"))
  end

  test "does not match non-package-manager bash commands (git)" do
    refute PreferPackageManager.matches?(policy_for("npm"), ctx("git commit -m 'fix'"))
  end

  test "does not match mix commands" do
    refute PreferPackageManager.matches?(policy_for("npm"), ctx("mix compile"))
  end

  test "does not match bare npm --version (no install verb)" do
    refute PreferPackageManager.matches?(policy_for("pnpm"), ctx("npm --version"))
  end

  test "does not match Read tool" do
    refute PreferPackageManager.matches?(policy_for("pnpm"), %Context{
             tool: "Read",
             resource_content: "npm install lodash"
           })
  end
end
