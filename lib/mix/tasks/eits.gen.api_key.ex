defmodule Mix.Tasks.Eits.Gen.ApiKey do
  use Mix.Task

  alias EyeInTheSky.Accounts.ApiKey

  @shortdoc "Generate and store a new API key for the EITS REST API"
  @moduledoc """
  Generates a cryptographically random API key, hashes it, and inserts a row
  into the `api_keys` table. The raw key is printed once — save it immediately.

  ## Usage

      mix eits.gen.api_key [--label LABEL] [--valid-until DATETIME]

  ## Options

    * `--label` - Human-readable label for this key (default: "default")
    * `--valid-until` - Optional expiry as ISO8601 datetime, e.g. "2027-01-01T00:00:00"

  ## Examples

      mix eits.gen.api_key
      mix eits.gen.api_key --label "ci-prod" --valid-until "2027-06-01T00:00:00"

  The raw key is shown once. It is NOT stored — only its HMAC-SHA256 hash is saved.
  """

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [label: :string, valid_until: :string]
      )

    label = Keyword.get(opts, :label, "default")
    valid_until_str = Keyword.get(opts, :valid_until)

    valid_until =
      case valid_until_str do
        nil ->
          nil

        s ->
          case NaiveDateTime.from_iso8601(s) do
            {:ok, dt} ->
              dt

            {:error, _} ->
              Mix.raise("Invalid --valid-until format. Use ISO8601: 2027-01-01T00:00:00")
          end
      end

    # Start only the repos needed; do not start the full supervision tree.
    Mix.Task.run("app.start")

    key = :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)

    case ApiKey.create(key, label, valid_until) do
      {:ok, api_key} ->
        expiry_note =
          if api_key.valid_until,
            do: "Expires: #{NaiveDateTime.to_iso8601(api_key.valid_until)}",
            else: "Expires: never"

        Mix.shell().info("""

        EITS API Key generated and stored:

          #{key}

        Label:   #{api_key.label}
        ID:      #{api_key.id}
        #{expiry_note}

        This is the only time the raw key will be shown. Save it now.

        The eits CLI picks it up via EITS_API_KEY or via Bearer token in Authorization header.
        """)

      {:error, changeset} ->
        Mix.raise("Failed to insert API key: #{inspect(changeset.errors)}")
    end
  end
end
