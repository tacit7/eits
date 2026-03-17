defmodule EyeInTheSkyWeb.Workers.EmbedNoteWorker do
  @moduledoc """
  Oban job: fetches a note, calls OpenAI text-embedding-3-small, and stores
  the resulting vector on the note. Failure is non-fatal — the note remains
  searchable via FTS.
  """

  use Oban.Worker, queue: :embeddings, max_attempts: 3

  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Notes.Note

  import Ecto.Query, warn: false
  import Ecto.Changeset, only: [change: 2]

  @model "text-embedding-3-small"
  @openai_url "https://api.openai.com/v1/embeddings"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"note_id" => note_id}}) do
    with {:ok, note} <- fetch_note(note_id),
         {:ok, vector} <- embed(note),
         {:ok, _} <- store(note, vector) do
      :ok
    else
      {:error, :not_found} ->
        # Note was deleted before we ran — not an error
        :ok

      {:error, :no_api_key} ->
        # Key not configured — skip silently, don't retry
        {:cancel, "OPENAI_API_KEY not configured"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Private ─────────────────────────────────────────────────────────────────

  defp fetch_note(note_id) do
    case Repo.get(Note, note_id) do
      nil -> {:error, :not_found}
      note -> {:ok, note}
    end
  end

  defp embed(note) do
    api_key = Application.get_env(:eye_in_the_sky_web, :openai_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, :no_api_key}
    else
      input = build_input(note)
      call_openai(api_key, input)
    end
  end

  defp build_input(%Note{title: title, body: body}) do
    [title, body]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join("\n\n")
  end

  defp call_openai(api_key, input) do
    body = Jason.encode!(%{model: @model, input: input})

    request =
      Finch.build(
        :post,
        @openai_url,
        [
          {"Authorization", "Bearer #{api_key}"},
          {"Content-Type", "application/json"}
        ],
        body
      )

    case Finch.request(request, EyeInTheSkyWeb.Finch) do
      {:ok, %Finch.Response{status: 200, body: resp_body}} ->
        parse_embedding(resp_body)

      {:ok, %Finch.Response{status: status, body: resp_body}} ->
        {:error, "OpenAI API error #{status}: #{resp_body}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp parse_embedding(body) do
    case Jason.decode(body) do
      {:ok, %{"data" => [%{"embedding" => vector} | _]}} ->
        {:ok, Pgvector.new(vector)}

      {:ok, resp} ->
        {:error, "Unexpected OpenAI response: #{inspect(resp)}"}

      {:error, reason} ->
        {:error, "Failed to parse OpenAI response: #{inspect(reason)}"}
    end
  end

  defp store(%Note{} = note, vector) do
    note
    |> change(embedding: vector, embedding_model: @model)
    |> Repo.update()
  end
end
