defmodule EyeInTheSky.RedactionTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Redaction

  describe "redact/1 — provider-specific patterns" do
    test "redacts OpenRouter sk-or- keys" do
      assert Redaction.redact("bad key sk-or-abcdef1234567890xyz here") ==
               "bad key [redacted] here"
    end

    test "redacts generic sk- keys" do
      assert Redaction.redact("Bearer sk-abcdef1234567890") =~ "[redacted]"
      refute Redaction.redact("Bearer sk-abcdef1234567890") =~ "sk-abcdef"
    end

    test "redacts GitHub PATs (classic)" do
      assert Redaction.redact("token ghp_abcdef1234567890ABCD end") =~ "[redacted]"
      refute Redaction.redact("token ghp_abcdef1234567890ABCD end") =~ "ghp_abcdef"
    end

    test "redacts GitHub fine-grained PATs" do
      input = "github_pat_11ABCDEFG1234567890abcdefghij done"
      out = Redaction.redact(input)
      assert out =~ "[redacted]"
      refute out =~ "github_pat_11"
    end

    test "redacts Groq gsk_ keys" do
      out = Redaction.redact("gsk_abcdef1234567890ABCD here")
      assert out =~ "[redacted]"
      refute out =~ "gsk_abcdef"
    end

    test "redacts Google AIza keys" do
      out = Redaction.redact("AIzaSyABCDEFGHIJKLMNOPQRSTUVWXYZ0123456 here")
      assert out =~ "[redacted]"
      refute out =~ "AIzaSy"
    end

    test "redacts key_ / token_ prefixes" do
      assert Redaction.redact("key-abcdef1234 x") =~ "[redacted]"
      assert Redaction.redact("token_abcdef1234 x") =~ "[redacted]"
    end
  end

  describe "redact/1 — generic long blob backstop" do
    test "redacts a long opaque blob after ':' boundary" do
      out = Redaction.redact("Authorization: abcdefghijklmnopqrstuvwxyz0123456789")
      assert out =~ "[redacted]"
      refute out =~ "abcdefghijklmnopqrstuvwxyz"
    end

    test "redacts a long opaque blob after '=' boundary" do
      out = Redaction.redact("api_secret=abcdefghijklmnopqrstuvwxyz0123456789")
      assert out =~ "[redacted]"
    end

    test "does not redact short identifiers" do
      assert Redaction.redact("id: abc123") == "id: abc123"
    end

    test "leaves short prose intact" do
      assert Redaction.redact("provider error: rate limited") ==
               "provider error: rate limited"
    end
  end

  describe "redact/1 — passthrough" do
    test "returns non-binary unchanged" do
      assert Redaction.redact(nil) == nil
      assert Redaction.redact(:atom) == :atom
      assert Redaction.redact({:tuple, 1}) == {:tuple, 1}
    end
  end

  describe "redact_inspect/2" do
    test "inspects and redacts an error tuple that echoes a key" do
      out = Redaction.redact_inspect({:pi_control, "invalid key sk-or-abc123def456ghi789jkl"})
      refute out =~ "sk-or-abc123def456"
      assert out =~ "[redacted]"
    end

    test "truncates to :limit chars" do
      long = String.duplicate("a", 2000)
      out = Redaction.redact_inspect(long, limit: 100)
      assert byte_size(out) <= 100
    end
  end
end
