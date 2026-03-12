defmodule EyeInTheSkyWeb.Notifications do
  @moduledoc """
  Context for creating and managing notifications.

  Agents, cron jobs, and system code can call `notify/2` to create
  persistent notifications visible in the UI.
  """

  import Ecto.Query
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Notifications.Notification
  alias EyeInTheSkyWeb.PushSubscriptions

  @pubsub EyeInTheSkyWeb.PubSub
  @topic "notifications"

  @doc """
  Create a notification and broadcast it via PubSub.

  ## Examples

      notify("Job completed", category: :job)
      notify("Agent finished", category: :agent, resource: {"session", "abc-123"})
      notify("Disk space low", category: :system, body: "Only 2GB remaining")
  """
  def notify(title, opts \\ []) do
    category = opts[:category] |> to_string() |> normalize_category()
    {resource_type, resource_id} = opts[:resource] || {nil, nil}

    attrs = %{
      title: title,
      body: opts[:body],
      category: category,
      resource_type: resource_type && to_string(resource_type),
      resource_id: resource_id && to_string(resource_id)
    }

    case create_notification(attrs) do
      {:ok, notification} ->
        broadcast(:notification_created, notification)
        maybe_push(notification)
        {:ok, notification}

      error ->
        error
    end
  end

  def create_notification(attrs) do
    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
  end

  def list_notifications(opts \\ []) do
    limit = opts[:limit] || 50

    Notification
    |> order_by([n], desc: n.inserted_at, desc: n.id)
    |> limit(^limit)
    |> Repo.all()
  end

  def unread_count do
    Notification
    |> where(read: false)
    |> Repo.aggregate(:count)
  end

  def mark_read(id) do
    result =
      Notification
      |> Repo.get!(id)
      |> Ecto.Changeset.change(read: true)
      |> Repo.update()

    with {:ok, notification} <- result do
      broadcast(:notification_read, notification.id)
    end

    result
  end

  def mark_all_read do
    {count, _} =
      Notification
      |> where(read: false)
      |> Repo.update_all(set: [read: true])

    broadcast(:notifications_updated)
    {:ok, count}
  end

  def purge_old(days \\ 7) do
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-days * 86400, :second)

    {count, _} =
      Notification
      |> where([n], n.inserted_at < ^cutoff)
      |> Repo.delete_all()

    {:ok, count}
  end

  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  defp broadcast(event, payload \\ nil) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {event, payload})
  end

  defp maybe_push(%{category: "agent"} = notification) do
    Task.start(fn ->
      PushSubscriptions.broadcast(notification.title, notification.body)
    end)
  end

  defp maybe_push(_notification), do: :ok

  defp normalize_category("agent"), do: "agent"
  defp normalize_category("job"), do: "job"
  defp normalize_category(_), do: "system"
end
