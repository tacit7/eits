defmodule EyeInTheSky.Notifications do
  @moduledoc """
  Context for creating and managing notifications.

  Agents, cron jobs, and system code can call `notify/2` to create
  persistent notifications visible in the UI.
  """

  import Ecto.Query
  alias EyeInTheSky.Notifications.Notification
  alias EyeInTheSky.PushSubscriptions
  alias EyeInTheSky.Repo

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
      resource_type: if(resource_type, do: to_string(resource_type)),
      resource_id: if(resource_id, do: to_string(resource_id))
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
    category = opts[:category]

    Notification
    |> then(fn q ->
      if category && category != "all",
        do: where(q, [n], n.category == ^category),
        else: q
    end)
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
    case Repo.get(Notification, id) do
      nil ->
        {:error, :not_found}

      notification ->
        result =
          notification
          |> Notification.changeset(%{read: true})
          |> Repo.update()

        with {:ok, updated} <- result do
          broadcast(:notification_read, updated.id)
        end

        result
    end
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
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-days * 86_400, :second)

    {count, _} =
      Notification
      |> where([n], n.inserted_at < ^cutoff)
      |> Repo.delete_all()

    {:ok, count}
  end

  def subscribe do
    EyeInTheSky.Events.subscribe_notifications()
  end

  defp broadcast(event, payload \\ nil) do
    EyeInTheSky.Events.notification(event, payload)
    sync_dock_badge()
  end

  defp sync_dock_badge do
    EyeInTheSky.Desktop.set_badge(unread_count())
  end

  defp maybe_push(%{category: "agent"} = notification) do
    url = build_url(notification.resource_type, notification.resource_id)

    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      PushSubscriptions.broadcast(notification.title, notification.body, url)
    end)
  end

  defp maybe_push(_notification), do: :ok

  defp build_url("session", id) when is_binary(id), do: "/dm/#{id}"
  defp build_url(_type, _id), do: nil

  defp normalize_category("agent"), do: "agent"
  defp normalize_category("job"), do: "job"
  defp normalize_category(_), do: "system"
end
