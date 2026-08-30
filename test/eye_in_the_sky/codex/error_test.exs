defmodule EyeInTheSky.Codex.ErrorTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Codex.Error

  test "normalizes nested Codex error JSON" do
    json =
      Jason.encode!(%{
        "type" => "error",
        "status" => 400,
        "error" => %{
          "type" => "invalid_request_error",
          "message" =>
            "The 'gpt-5.2' model is not supported when using Codex with a ChatGPT account."
        }
      })

    normalized = Error.normalize(json)

    assert normalized.message ==
             "The 'gpt-5.2' model is not supported when using Codex with a ChatGPT account."

    assert normalized.status == 400
    assert normalized.error_type == "invalid_request_error"
    assert normalized.model == "gpt-5.2"
  end

  test "detects unsupported model errors" do
    assert Error.unsupported_model?("The 'gpt-5.2' model is not supported")
    refute Error.unsupported_model?("temporary network error")
  end
end
