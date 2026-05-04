defmodule EyeInTheSky.IAM.Builtin.BlockAwsCli do
  @moduledoc """
  Deny Bash invocations of destructive AWS CLI operations.

  Blocked patterns:
    * `aws ec2 terminate-instances`
    * `aws ec2 stop-instances`
    * `aws s3 rm --recursive` / `aws s3 rb`
    * `aws iam delete-*`
    * `aws rds delete-*`
    * `aws lambda delete-function`
    * `aws cloudformation delete-stack`
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @destructive_re ~r/\baws\s+(?:
    ec2\s+(?:terminate-instances|stop-instances)|
    s3\s+(?:rm\b.*--recursive|rb\b)|
    iam\s+delete-|
    rds\s+delete-|
    lambda\s+delete-function|
    cloudformation\s+delete-stack
  )/xi

  @impl true
  def matches?(%Policy{} = _p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    Regex.match?(@destructive_re, cmd)
  end

  def matches?(_, _), do: false
end
