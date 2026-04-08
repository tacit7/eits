defmodule EyeInTheSky.Auth.WebAuthnHelpers do
  @moduledoc """
  Wax library integration helpers for serializing and deserializing WebAuthn
  challenge structs and COSE public keys to/from JSON-safe representations.

  Used by `EyeInTheSkyWeb.AuthController` to store challenges in the session
  without relying on `:erlang.term_to_binary/1`.
  """

  @doc "Serialize a `Wax.Challenge` struct to a JSON string."
  def serialize_challenge(%Wax.Challenge{} = c) do
    allow_creds =
      Enum.map(c.allow_credentials, fn {cred_id, cose_key} ->
        %{
          "cred_id" => Base.encode64(cred_id),
          "cose_key" => serialize_cose_key(cose_key)
        }
      end)

    %{
      "type" => Atom.to_string(c.type),
      "bytes" => Base.encode64(c.bytes),
      "origin" => c.origin,
      "rp_id" => c.rp_id,
      "token_binding_status" => c.token_binding_status,
      "issued_at" => c.issued_at,
      "allow_credentials" => allow_creds,
      "attestation" => c.attestation,
      "timeout" => c.timeout,
      "trusted_attestation_types" => Enum.map(c.trusted_attestation_types, &Atom.to_string/1),
      "user_verification" => c.user_verification,
      "verify_trust_root" => c.verify_trust_root,
      "silent_authentication_enabled" => c.silent_authentication_enabled,
      "android_key_allow_software_enforcement" => c.android_key_allow_software_enforcement,
      "acceptable_authenticator_statuses" => c.acceptable_authenticator_statuses
    }
    |> Jason.encode!()
  end

  @doc "Deserialize a JSON string back to a `Wax.Challenge` struct."
  def deserialize_challenge(json_str) do
    m = Jason.decode!(json_str)

    allow_creds =
      Enum.map(m["allow_credentials"] || [], fn ac ->
        {Base.decode64!(ac["cred_id"]), deserialize_cose_key(ac["cose_key"])}
      end)

    %Wax.Challenge{
      type: String.to_existing_atom(m["type"]),
      bytes: Base.decode64!(m["bytes"]),
      origin: m["origin"],
      rp_id: m["rp_id"],
      token_binding_status: m["token_binding_status"],
      issued_at: m["issued_at"],
      allow_credentials: allow_creds,
      attestation: m["attestation"],
      timeout: m["timeout"],
      trusted_attestation_types:
        Enum.map(m["trusted_attestation_types"], &String.to_existing_atom/1),
      user_verification: m["user_verification"],
      verify_trust_root: m["verify_trust_root"],
      silent_authentication_enabled: m["silent_authentication_enabled"],
      android_key_allow_software_enforcement: m["android_key_allow_software_enforcement"],
      acceptable_authenticator_statuses: m["acceptable_authenticator_statuses"],
      origin_verify_fun: {Wax, :origins_match?, []}
    }
  end

  @doc """
  Serialize a COSE key map (integer keys, possibly binary values) to a
  JSON-safe map with string keys. Binary values are wrapped as `%{"b64" => ...}`.
  """
  def serialize_cose_key(cose_map) do
    Map.new(cose_map, fn {k, v} ->
      val = if is_binary(v) and not String.valid?(v), do: %{"b64" => Base.encode64(v)}, else: v
      {Integer.to_string(k), val}
    end)
  end

  @doc "Deserialize a JSON-safe COSE key map back to integer keys with binary values decoded."
  def deserialize_cose_key(map) do
    Map.new(map, fn {k, v} ->
      val = if is_map(v) and Map.has_key?(v, "b64"), do: Base.decode64!(v["b64"]), else: v
      {String.to_integer(k), val}
    end)
  end
end
