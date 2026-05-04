defmodule EyeInTheSky.IAM.Builtin.BlockSecretsWrite do
  @moduledoc """
  Deny Write/Edit/MultiEdit tool calls targeting private key and certificate
  files: `.pem`, `.key`, `.pfx`, `.p12`, `.crt`, `.cer`, `id_rsa`,
  `id_ed25519`, `id_ecdsa`, `id_dsa`, and any file under `~/.ssh/`.

  Writing to these files can overwrite SSH identities, TLS certificates, or
  private keys — often irreversibly and silently.

  Supports an `"allowPaths"` condition entry — a list of exact path strings
  that are permitted (e.g. generated self-signed certs in a test fixture dir).
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @secret_ext_re ~r/\.(?:pem|key|pfx|p12|crt|cer)$/i
  @secret_name_re ~r/(?:^|\/)id_(?:rsa|ed25519|ecdsa|dsa)(?:\.pub)?$/
  @ssh_dir_re ~r{(?:^|/)\.ssh/}

  @write_tools ~w(Write Edit MultiEdit)

  @impl true
  def matches?(%Policy{} = p, %Context{tool: tool, resource_path: path})
      when tool in @write_tools and is_binary(path) do
    if secret_path?(path), do: not allowed?(path, p), else: false
  end

  def matches?(_, _), do: false

  defp secret_path?(path) do
    Regex.match?(@secret_ext_re, path) or
      Regex.match?(@secret_name_re, path) or
      Regex.match?(@ssh_dir_re, path)
  end

  defp allowed?(path, %Policy{condition: %{} = cond}) do
    paths = Map.get(cond, "allowPaths") || Map.get(cond, :allowPaths) || []
    Enum.any?(paths, &(&1 == path))
  end

  defp allowed?(_, _), do: false
end
