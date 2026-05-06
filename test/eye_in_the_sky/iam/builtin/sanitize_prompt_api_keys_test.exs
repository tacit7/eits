defmodule EyeInTheSky.IAM.Builtin.SanitizePromptApiKeysTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.SanitizePromptApiKeys
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(prompt), do: %Context{prompt: prompt}

  describe "redact/1" do
    test "redacts Anthropic API keys" do
      {redacted, count, summary} =
        SanitizePromptApiKeys.redact("key: sk-ant-aBcDeFgHiJkLmNoPqRsT0")

      assert redacted == "key: [REDACTED:anthropic]"
      assert count == 1
      assert summary == "Redacted: anthropic (1)"
    end

    test "redacts OpenAI API keys" do
      {redacted, count, _} = SanitizePromptApiKeys.redact("sk-aBcDeFgHiJkLmNoPqRsTu")

      assert redacted == "[REDACTED:openai]"
      assert count == 1
    end

    test "redacts GitHub personal access tokens ghp_" do
      {redacted, count, _} =
        SanitizePromptApiKeys.redact("ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")

      assert redacted == "[REDACTED:github]"
      assert count == 1
    end

    test "redacts GitHub OAuth tokens gho_" do
      {redacted, count, _} =
        SanitizePromptApiKeys.redact("gho_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")

      assert redacted == "[REDACTED:github]"
      assert count == 1
    end

    test "redacts AWS access keys" do
      {redacted, count, _} = SanitizePromptApiKeys.redact("key is AKIAIOSFODNN7EXAMPLE here")

      assert redacted == "key is [REDACTED:aws] here"
      assert count == 1
    end

    test "redacts generic api_key patterns" do
      {redacted, count, _} = SanitizePromptApiKeys.redact("api_key=supersecretvalue123456")

      assert String.contains?(redacted, "[REDACTED:generic]")
      assert count == 1
    end

    test "redacts multiple secrets in one string" do
      text = "ant: sk-ant-12345678901234567890 and oai: sk-09876543210987654321"
      {redacted, count, summary} = SanitizePromptApiKeys.redact(text)

      assert count == 2
      assert String.contains?(redacted, "[REDACTED:anthropic]")
      assert String.contains?(redacted, "[REDACTED:openai]")
      assert summary =~ "anthropic"
      assert summary =~ "openai"
    end

    test "leaves benign text untouched" do
      text = "hello world, no secrets here"
      {redacted, count, summary} = SanitizePromptApiKeys.redact(text)

      assert redacted == text
      assert count == 0
      assert summary == nil
    end

    test "handles empty string" do
      {redacted, count, summary} = SanitizePromptApiKeys.redact("")

      assert redacted == ""
      assert count == 0
      assert summary == nil
    end
  end

  describe "matches?/2" do
    test "matches when prompt contains Anthropic key" do
      assert SanitizePromptApiKeys.matches?(%Policy{}, ctx("sk-ant-abcdefghij1234567890"))
    end

    test "matches when prompt contains OpenAI key" do
      assert SanitizePromptApiKeys.matches?(%Policy{}, ctx("sk-abcdefghij1234567890"))
    end

    test "matches when prompt contains AWS access key" do
      assert SanitizePromptApiKeys.matches?(%Policy{}, ctx("AKIAIOSFODNN7EXAMPLE"))
    end

    test "does not match benign text" do
      refute SanitizePromptApiKeys.matches?(%Policy{}, ctx("normal text no secrets"))
    end

    test "does not match when prompt is nil" do
      refute SanitizePromptApiKeys.matches?(%Policy{}, %Context{prompt: nil})
    end

    test "does not match context without prompt" do
      refute SanitizePromptApiKeys.matches?(%Policy{}, %Context{tool: "Bash"})
    end
  end

  describe "instruction_message/2" do
    test "returns redacted content with summary" do
      msg =
        SanitizePromptApiKeys.instruction_message(
          %Policy{},
          ctx("here is my key: sk-ant-abcdefghij1234567890")
        )

      assert String.contains?(msg, "[REDACTED:anthropic]")
      assert String.contains?(msg, "Redacted:")
    end

    test "returns nil when prompt is nil" do
      assert SanitizePromptApiKeys.instruction_message(%Policy{}, %Context{prompt: nil}) == nil
    end
  end
end
