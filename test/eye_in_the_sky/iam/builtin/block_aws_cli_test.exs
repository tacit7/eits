defmodule EyeInTheSky.IAM.Builtin.BlockAwsCliTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.BlockAwsCli
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}

  test "blocks aws ec2 terminate-instances" do
    assert BlockAwsCli.matches?(
             %Policy{},
             ctx("aws ec2 terminate-instances --instance-ids i-123")
           )
  end

  test "blocks aws ec2 stop-instances" do
    assert BlockAwsCli.matches?(%Policy{}, ctx("aws ec2 stop-instances --instance-ids i-123"))
  end

  test "blocks aws s3 rm --recursive" do
    assert BlockAwsCli.matches?(%Policy{}, ctx("aws s3 rm s3://my-bucket --recursive"))
  end

  test "blocks aws s3 rb" do
    assert BlockAwsCli.matches?(%Policy{}, ctx("aws s3 rb s3://my-bucket --force"))
  end

  test "blocks aws iam delete-user" do
    assert BlockAwsCli.matches?(%Policy{}, ctx("aws iam delete-user --user-name alice"))
  end

  test "blocks aws rds delete-db-instance" do
    assert BlockAwsCli.matches?(
             %Policy{},
             ctx("aws rds delete-db-instance --db-instance-identifier mydb")
           )
  end

  test "blocks aws lambda delete-function" do
    assert BlockAwsCli.matches?(
             %Policy{},
             ctx("aws lambda delete-function --function-name my-fn")
           )
  end

  test "blocks aws cloudformation delete-stack" do
    assert BlockAwsCli.matches?(
             %Policy{},
             ctx("aws cloudformation delete-stack --stack-name my-stack")
           )
  end

  test "does not block aws s3 ls" do
    refute BlockAwsCli.matches?(%Policy{}, ctx("aws s3 ls s3://my-bucket"))
  end

  test "does not block aws ec2 describe-instances" do
    refute BlockAwsCli.matches?(%Policy{}, ctx("aws ec2 describe-instances"))
  end

  test "does not match non-Bash tool" do
    refute BlockAwsCli.matches?(%Policy{}, %Context{
             tool: "Write",
             resource_content: "aws ec2 terminate-instances"
           })
  end
end
