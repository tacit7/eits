defmodule EyeInTheSky.IAM.Builtin.BlockTerraformTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.BlockTerraform
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}
  defp policy(cond \\ nil), do: %Policy{condition: cond}

  test "blocks terraform destroy" do
    assert BlockTerraform.matches?(policy(), ctx("terraform destroy"))
  end

  test "blocks terraform apply" do
    assert BlockTerraform.matches?(policy(), ctx("terraform apply -auto-approve"))
  end

  test "does not block terraform plan" do
    refute BlockTerraform.matches?(policy(), ctx("terraform plan"))
  end

  test "does not block terraform init" do
    refute BlockTerraform.matches?(policy(), ctx("terraform init"))
  end

  test "does not block terraform fmt" do
    refute BlockTerraform.matches?(policy(), ctx("terraform fmt"))
  end

  test "does not match non-Bash tool" do
    refute BlockTerraform.matches?(policy(), %Context{tool: "Write", resource_content: "terraform destroy"})
  end

  test "allowCommands escapes the block" do
    p = policy(%{"allowCommands" => ["apply"]})
    refute BlockTerraform.matches?(p, ctx("terraform apply"))
    assert BlockTerraform.matches?(p, ctx("terraform destroy"))
  end
end
