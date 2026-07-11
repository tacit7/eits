defmodule EyeInTheSky.Instance do
  @moduledoc """
  Per-process-instance namespace generation.

  `namespace/0` returns an 8-byte Base64url token that is generated once at
  application start and stored in `:persistent_term`. It scopes temp files to
  a single running instance of the app, preventing collisions when multiple
  instances share the same temp directory.

  Not persisted across restarts — each new app start gets a fresh namespace.
  """

  @key {__MODULE__, :namespace}

  @doc "Initialize the namespace. Called from application.ex before supervision tree starts."
  def init do
    token =
      :crypto.strong_rand_bytes(8)
      |> Base.url_encode64(padding: false)

    :persistent_term.put(@key, token)
  end

  @doc "Returns the current instance namespace string."
  def namespace, do: :persistent_term.get(@key)
end
