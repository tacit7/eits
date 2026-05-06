defmodule EyeInTheSky.IAM.Builtin.BlockAzCliTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.BlockAzCli
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}

  test "blocks az vm delete" do
    assert BlockAzCli.matches?(%Policy{}, ctx("az vm delete --name my-vm --resource-group rg"))
  end

  test "blocks az group delete" do
    assert BlockAzCli.matches?(%Policy{}, ctx("az group delete --name my-rg --yes"))
  end

  test "blocks az sql db delete" do
    assert BlockAzCli.matches?(
             %Policy{},
             ctx("az sql db delete --name mydb --server srv --resource-group rg")
           )
  end

  test "blocks az aks delete" do
    assert BlockAzCli.matches?(
             %Policy{},
             ctx("az aks delete --name my-cluster --resource-group rg")
           )
  end

  test "blocks az webapp delete" do
    assert BlockAzCli.matches?(
             %Policy{},
             ctx("az webapp delete --name my-app --resource-group rg")
           )
  end

  test "blocks az functionapp delete" do
    assert BlockAzCli.matches?(
             %Policy{},
             ctx("az functionapp delete --name my-fn --resource-group rg")
           )
  end

  test "does not block az vm list" do
    refute BlockAzCli.matches?(%Policy{}, ctx("az vm list --resource-group rg"))
  end

  test "does not block az group list" do
    refute BlockAzCli.matches?(%Policy{}, ctx("az group list"))
  end

  test "does not match non-Bash tool" do
    refute BlockAzCli.matches?(%Policy{}, %Context{
             tool: "Write",
             resource_content: "az vm delete --name x"
           })
  end
end
