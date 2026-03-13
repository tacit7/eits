defmodule Mix.Tasks.Eits.Gen.ApiKey do
  use Mix.Task

  @shortdoc "Generate a random API key for the EITS REST API"
  @moduledoc """
  Generates a cryptographically random API key for securing the EITS REST API.

  ## Usage

      mix eits.gen.api_key

  Prints the key and instructions for setting it up in your environment
  and zshrc. The key is not stored — save it immediately.
  """

  @impl Mix.Task
  def run(_args) do
    key = :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)

    Mix.shell().info("""

    EITS API Key generated:

      #{key}

    Add to ~/.zshrc (or ~/.bashrc):

      export EITS_API_KEY="#{key}"

    Then reload your shell:

      source ~/.zshrc

    Start the server with the key set:

      EITS_API_KEY="#{key}" mix phx.server

    Or export it once and run normally:

      export EITS_API_KEY="#{key}"
      mix phx.server

    The eits CLI picks it up automatically from EITS_API_KEY.
    """)
  end
end
