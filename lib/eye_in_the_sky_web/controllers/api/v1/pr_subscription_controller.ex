defmodule EyeInTheSkyWeb.Api.V1.PrSubscriptionController do
  use EyeInTheSkyWeb, :controller

  alias EyeInTheSky.Github.PrSubscriptions

  def subscribe(conn, %{"pr_number" => pr_number, "repository_full_name" => repo, "session_uuid" => session_uuid}) do
    pr_number = parse_int(pr_number)

    case PrSubscriptions.subscribe(session_uuid, pr_number, repo) do
      {:ok, sub} ->
        conn |> put_status(201) |> json(%{id: sub.id, pr_number: sub.pr_number, repository_full_name: sub.repository_full_name, active: sub.active})

      {:error, changeset} ->
        conn |> put_status(422) |> json(%{error: "invalid", details: format_errors(changeset)})
    end
  end

  def subscribe(conn, _params) do
    conn |> put_status(400) |> json(%{error: "pr_number, repository_full_name, and session_uuid are required"})
  end

  def unsubscribe(conn, %{"pr_number" => pr_number, "repository_full_name" => repo, "session_uuid" => session_uuid}) do
    pr_number = parse_int(pr_number)
    PrSubscriptions.unsubscribe(session_uuid, pr_number, repo)
    json(conn, %{ok: true})
  end

  def unsubscribe(conn, _params) do
    conn |> put_status(400) |> json(%{error: "pr_number, repository_full_name, and session_uuid are required"})
  end

  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(val) when is_binary(val), do: String.to_integer(val)

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
