defmodule EyeInTheSky.IAM.Builtin.BlockEnvFilesTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.BlockEnvFiles
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp policy(cond \\ %{}), do: %Policy{condition: cond}

  test "blocks Read of .env" do
    ctx = %Context{tool: "Read", resource_path: "/project/.env"}
    assert BlockEnvFiles.matches?(policy(), ctx)
  end

  test "blocks Write of .env.production" do
    ctx = %Context{tool: "Write", resource_path: "/project/.env.production"}
    assert BlockEnvFiles.matches?(policy(), ctx)
  end

  test "blocks cat .env via Bash" do
    ctx = %Context{tool: "Bash", resource_content: "cat .env"}
    assert BlockEnvFiles.matches?(policy(), ctx)
  end

  test "does not block non-env paths" do
    ctx = %Context{tool: "Read", resource_path: "/project/config.env.ts"}
    refute BlockEnvFiles.matches?(policy(), ctx)
  end

  test "allowFiles escapes the deny" do
    p = policy(%{"allowFiles" => [".env.example"]})
    ctx = %Context{tool: "Read", resource_path: "/project/.env.example"}
    refute BlockEnvFiles.matches?(p, ctx)
  end
end
