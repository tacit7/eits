defmodule EyeInTheSky.IAM.Builtin.WarnGlobalPackageInstallTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.WarnGlobalPackageInstall
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}

  test "matches npm install -g" do
    assert WarnGlobalPackageInstall.matches?(%Policy{}, ctx("npm install -g typescript"))
  end

  test "matches npm i -g shorthand" do
    assert WarnGlobalPackageInstall.matches?(%Policy{}, ctx("npm i -g eslint"))
  end

  test "matches yarn global add" do
    assert WarnGlobalPackageInstall.matches?(%Policy{}, ctx("yarn global add prettier"))
  end

  test "matches pnpm add -g" do
    assert WarnGlobalPackageInstall.matches?(%Policy{}, ctx("pnpm add -g typescript"))
  end

  test "matches pnpm add --global" do
    assert WarnGlobalPackageInstall.matches?(%Policy{}, ctx("pnpm add --global typescript"))
  end

  test "matches pip install without venv" do
    assert WarnGlobalPackageInstall.matches?(%Policy{}, ctx("pip install requests"))
  end

  test "matches pip3 install without venv" do
    assert WarnGlobalPackageInstall.matches?(%Policy{}, ctx("pip3 install flask"))
  end

  test "matches brew install" do
    assert WarnGlobalPackageInstall.matches?(%Policy{}, ctx("brew install jq"))
  end

  test "does not match npm install (local)" do
    refute WarnGlobalPackageInstall.matches?(%Policy{}, ctx("npm install lodash"))
  end

  test "does not match pip install with --user flag" do
    refute WarnGlobalPackageInstall.matches?(%Policy{}, ctx("pip install --user requests"))
  end

  test "does not match non-Bash tool" do
    refute WarnGlobalPackageInstall.matches?(%Policy{}, %Context{
             tool: "Write",
             resource_content: "npm install -g x"
           })
  end
end
