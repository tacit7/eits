defmodule EyeInTheSky.IAM.Builtin.WarnPackagePublishTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.WarnPackagePublish
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}

  test "matches npm publish" do
    assert WarnPackagePublish.matches?(%Policy{}, ctx("npm publish"))
  end

  test "matches npm publish with tag" do
    assert WarnPackagePublish.matches?(%Policy{}, ctx("npm publish --tag latest"))
  end

  test "matches yarn publish" do
    assert WarnPackagePublish.matches?(%Policy{}, ctx("yarn publish"))
  end

  test "matches pnpm publish" do
    assert WarnPackagePublish.matches?(%Policy{}, ctx("pnpm publish --access public"))
  end

  test "matches mix hex.publish" do
    assert WarnPackagePublish.matches?(%Policy{}, ctx("mix hex.publish"))
  end

  test "matches cargo publish" do
    assert WarnPackagePublish.matches?(%Policy{}, ctx("cargo publish"))
  end

  test "matches gem push" do
    assert WarnPackagePublish.matches?(%Policy{}, ctx("gem push my-gem-1.0.0.gem"))
  end

  test "matches twine upload" do
    assert WarnPackagePublish.matches?(%Policy{}, ctx("twine upload dist/*"))
  end

  test "does not match npm install" do
    refute WarnPackagePublish.matches?(%Policy{}, ctx("npm install"))
  end

  test "does not match mix test" do
    refute WarnPackagePublish.matches?(%Policy{}, ctx("mix test"))
  end

  test "does not match non-Bash tool" do
    refute WarnPackagePublish.matches?(%Policy{}, %Context{tool: "Write", resource_content: "npm publish"})
  end
end
