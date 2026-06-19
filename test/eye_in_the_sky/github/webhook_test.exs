defmodule EyeInTheSky.Github.WebhookTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Github.Webhook

  @secret "test_secret"
  @body ~s({"action":"opened"})

  defp valid_sig(body \\ @body) do
    mac = :crypto.mac(:hmac, :sha256, @secret, body) |> Base.encode16(case: :lower)
    "sha256=#{mac}"
  end

  describe "verify/3" do
    test "returns :ok for valid signature" do
      assert :ok = Webhook.verify(valid_sig(), @body, @secret)
    end

    test "returns :error for tampered body" do
      assert :error = Webhook.verify(valid_sig(), "tampered", @secret)
    end

    test "returns :error for missing signature (nil)" do
      assert :error = Webhook.verify(nil, @body, @secret)
    end

    test "returns :error for missing sha256= prefix" do
      assert :error = Webhook.verify("abcdef1234", @body, @secret)
    end

    test "normalizes uppercase hex before compare" do
      mac = :crypto.mac(:hmac, :sha256, @secret, @body) |> Base.encode16(case: :upper)
      assert :ok = Webhook.verify("sha256=#{mac}", @body, @secret)
    end

    test "returns :error for non-hex characters in signature" do
      assert :error = Webhook.verify("sha256=" <> String.duplicate("z", 64), @body, @secret)
    end

    test "returns :error when hex is not 64 chars" do
      assert :error = Webhook.verify("sha256=abc123", @body, @secret)
    end
  end

  describe "secure_equal?/2" do
    test "returns false for different-length strings without timing side channel" do
      refute Webhook.secure_equal?("short", String.duplicate("x", 64))
    end
  end

  describe "normalize_event_type/2" do
    test "combines event header and action for PR events" do
      assert "pull_request.opened" = Webhook.normalize_event_type("pull_request", "opened")
    end

    test "returns just the header for push (no action)" do
      assert "push" = Webhook.normalize_event_type("push", nil)
    end

    test "returns just the header when action is empty string" do
      assert "check_run" = Webhook.normalize_event_type("check_run", "")
    end
  end
end
