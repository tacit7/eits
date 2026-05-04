defmodule EyeInTheSky.IAM.Builtin.SanitizeConnectionStringsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.SanitizeConnectionStrings
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(response), do: %Context{tool_response: response}

  test "matches postgresql URI with credentials" do
    assert SanitizeConnectionStrings.matches?(
             %Policy{},
             ctx("postgresql://admin:s3cr3t@db.example.com/mydb")
           )
  end

  test "matches postgres short scheme" do
    assert SanitizeConnectionStrings.matches?(
             %Policy{},
             ctx("postgres://user:pass@localhost:5432/app")
           )
  end

  test "matches mysql URI with credentials" do
    assert SanitizeConnectionStrings.matches?(
             %Policy{},
             ctx("mysql://root:hunter2@db.internal/prod")
           )
  end

  test "matches mongodb URI with credentials" do
    assert SanitizeConnectionStrings.matches?(
             %Policy{},
             ctx("mongodb://admin:pass@mongo.example.com/mydb")
           )
  end

  test "matches mongodb+srv URI" do
    assert SanitizeConnectionStrings.matches?(
             %Policy{},
             ctx("mongodb+srv://user:pass@cluster.mongodb.net/app")
           )
  end

  test "matches redis URI with password" do
    assert SanitizeConnectionStrings.matches?(
             %Policy{},
             ctx("redis://:mypassword@redis.example.com:6379")
           )
  end

  test "matches amqp URI with credentials" do
    assert SanitizeConnectionStrings.matches?(
             %Policy{},
             ctx("amqp://guest:guest@rabbitmq.internal/vhost")
           )
  end

  test "does not match postgresql URI without credentials" do
    refute SanitizeConnectionStrings.matches?(
             %Policy{},
             ctx("postgresql://db.example.com/mydb")
           )
  end

  test "does not match plain text with no URI" do
    refute SanitizeConnectionStrings.matches?(%Policy{}, ctx("connected to database successfully"))
  end

  test "does not match when tool_response is nil" do
    refute SanitizeConnectionStrings.matches?(%Policy{}, %Context{tool_response: nil})
  end

  test "matches URI embedded in larger output" do
    output = """
    Connecting to database...
    DSN: postgresql://app:secret123@prod-db.example.com/app_prod
    Connection established.
    """

    assert SanitizeConnectionStrings.matches?(%Policy{}, ctx(output))
  end
end
