defmodule EyeInTheSky.Sessions.Naming do
  @moduledoc false

  import Ecto.Query
  alias EyeInTheSky.{Events, Repo}
  alias EyeInTheSky.Sessions.Session

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-haiku-4-5-20251001"
  @max_prompt_chars 200
  @max_name_chars 60

  @system_prompt "You are a chat-session namer. Output ONLY a short descriptive name " <>
                   "(3–6 words, noun-preferring, no quotes, no markdown, no trailing punctuation). " <>
                   "Nothing else — just the name on a single line."

  @doc """
  Non-fatal auto-name. Only writes if the session name still equals `fallback_name` —
  the DB WHERE clause makes the guard atomic (no TOCTOU).
  """
  def try_auto_name(session_id, body, fallback_name) do
    with {:ok, generated_name} <- generate_name(body),
         {1, [updated_session]} <-
           Repo.update_all(
             from(s in Session,
               where: s.id == ^session_id and s.name == ^fallback_name,
               select: s
             ),
             set: [name: generated_name]
           ) do
      Events.broadcast_rail_session_updated(updated_session)
    else
      _ -> :ok
    end
  end

  @doc "Returns `{:ok, name}` or `{:error, reason}`. Never raises."
  def generate_name(body) do
    api_key = System.get_env("ANTHROPIC_API_KEY", "")

    if api_key == "" do
      {:error, :no_api_key}
    else
      prompt_text = String.slice(body, 0, @max_prompt_chars)

      case Req.post(@api_url,
             json: %{
               model: @model,
               max_tokens: 20,
               system: @system_prompt,
               messages: [
                 %{
                   role: "user",
                   content: "Name this chat session based on the opening message:\n\n#{prompt_text}"
                 }
               ]
             },
             headers: [
               {"x-api-key", api_key},
               {"anthropic-version", "2023-06-01"}
             ],
             receive_timeout: 10_000
           ) do
        {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
          name =
            text
            |> String.trim()
            |> String.trim("\"")
            |> String.trim("'")
            |> String.slice(0, @max_name_chars)

          if name == "", do: {:error, :empty_name}, else: {:ok, name}

        {:ok, %{status: status}} ->
          {:error, {:api_error, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
