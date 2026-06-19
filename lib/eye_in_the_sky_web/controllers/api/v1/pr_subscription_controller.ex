defmodule EyeInTheSkyWeb.Api.V1.PrSubscriptionController do
  use EyeInTheSkyWeb, :controller

  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.Github.PrSubscriptions

  def subscribe(conn, %{
        "pr_number" => pr_number,
        "repository_full_name" => repo,
        "session_uuid" => session_uuid
      }) do
    pr_number = parse_int(pr_number)

    if is_nil(pr_number) do
      conn |> put_status(400) |> json(%{error: "pr_number must be an integer"})
    else

      case PrSubscriptions.subscribe(session_uuid, pr_number, repo) do
        {:ok, sub} ->
          conn
          |> put_status(201)
          |> json(%{
            id: sub.id,
            pr_number: sub.pr_number,
            repository_full_name: sub.repository_full_name,
            active: sub.active
          })

        {:error, changeset} ->
          conn |> put_status(422) |> json(%{error: "invalid", details: format_errors(changeset)})
      end
    end
  end

  def subscribe(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "pr_number, repository_full_name, and session_uuid are required"})
  end

  def unsubscribe(conn, %{
        "pr_number" => pr_number,
        "repository_full_name" => repo,
        "session_uuid" => session_uuid
      }) do
    case parse_int(pr_number) do
      nil ->
        conn |> put_status(400) |> json(%{error: "pr_number must be an integer"})

      pr_int ->
        PrSubscriptions.unsubscribe(session_uuid, pr_int, repo)
        json(conn, %{ok: true})
    end
  end

  def unsubscribe(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "pr_number, repository_full_name, and session_uuid are required"})
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
