defmodule EyeInTheSky.Github.EventContext do
  @moduledoc false

  defstruct [
    :delivery_id,
    :event_type,
    :repository_full_name,
    :sender_login,
    :github_pr_id,
    :pr_number,
    :head_branch,
    :base_branch,
    labels: [],
    draft?: false,
    merged?: false
  ]

  @doc "Build a normalized EventContext from a delivery map (string or atom keys in payload)."
  def from_delivery(delivery) do
    payload = delivery.payload || %{}
    event_type = delivery.event_type

    %__MODULE__{
      delivery_id: delivery.delivery_id,
      event_type: event_type,
      repository_full_name: delivery.repository_full_name,
      sender_login: delivery.sender_login
    }
    |> extract_fields(event_type, payload)
  end

  defp extract_fields(ctx, "pull_request" <> _, payload) do
    pr = payload["pull_request"] || %{}

    %{
      ctx
      | github_pr_id: pr["id"],
        pr_number: pr["number"],
        head_branch: get_in(pr, ["head", "ref"]),
        base_branch: get_in(pr, ["base", "ref"]),
        labels: Enum.map(pr["labels"] || [], & &1["name"]),
        draft?: pr["draft"] == true,
        merged?: pr["merged"] == true
    }
  end

  defp extract_fields(ctx, "push", payload) do
    ref = payload["ref"] || ""
    head = String.replace_prefix(ref, "refs/heads/", "")
    %{ctx | head_branch: if(head == "", do: nil, else: head)}
  end

  defp extract_fields(ctx, "check_run" <> _, payload) do
    head_branch = get_in(payload, ["check_run", "check_suite", "head_branch"])
    %{ctx | head_branch: head_branch}
  end

  defp extract_fields(ctx, _, _), do: ctx
end
