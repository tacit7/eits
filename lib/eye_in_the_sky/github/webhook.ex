defmodule EyeInTheSky.Github.Webhook do
  @moduledoc false

  @doc "Verify X-Hub-Signature-256 header against the raw body and secret."
  # When no secret is configured (e.g. local dev via smee), skip verification.
  def verify(_sig_header, _raw_body, ""), do: :ok
  def verify(_sig_header, _raw_body, nil), do: :ok

  def verify(sig_header, raw_body, secret) when is_binary(sig_header) do
    with "sha256=" <> hex <- sig_header,
         hex <- String.downcase(hex),
         true <- Regex.match?(~r/\A[0-9a-f]{64}\z/, hex),
         expected <-
           :crypto.mac(:hmac, :sha256, secret, raw_body) |> Base.encode16(case: :lower),
         true <- secure_equal?(hex, expected) do
      :ok
    else
      _ -> :error
    end
  end

  def verify(_, _, _), do: :error

  @doc "Normalize event header + payload action into a dotted event_type string."
  def normalize_event_type(event_header, action)
      when is_binary(action) and action != "",
      do: "#{event_header}.#{action}"

  def normalize_event_type(event_header, _), do: event_header

  @doc "Constant-time string equality; returns false immediately for length mismatch."
  def secure_equal?(left, right) when byte_size(left) == byte_size(right),
    do: Plug.Crypto.secure_compare(left, right)

  def secure_equal?(_, _), do: false
end
