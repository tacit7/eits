defmodule Mix.Tasks.Eits.Register do
  use Mix.Task

  @shortdoc "Generate a one-time passkey registration link for a user"
  @moduledoc """
  Generates a one-time passkey registration URL for the given username.

  ## Usage

      mix eits.register <username>

  The link is valid for 15 minutes. Open it in a browser to register a passkey.
  """

  @impl Mix.Task
  def run([username]) do
    Application.ensure_all_started(:eye_in_the_sky_web)

    case EyeInTheSkyWeb.Accounts.create_registration_token(username) do
      {:ok, raw_token, _rt} ->
        origin = Application.get_env(:wax_, :origin, "https://localhost:5001")
        url = "#{origin}/auth/register?token=#{raw_token}"
        Mix.shell().info("\nPasskey registration link for #{username}:")
        Mix.shell().info("  #{url}")
        Mix.shell().info("\nExpires in 15 minutes. Open this URL in your browser.\n")

      {:error, reason} ->
        Mix.shell().error("Failed to create token: #{inspect(reason)}")
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix eits.register <username>")
  end
end
