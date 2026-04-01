defmodule EyeInTheSky.NotificationsTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.Notifications

  defp uniq, do: System.unique_integer([:positive])

  test "notify/2 creates a notification with defaults" do
    {:ok, n} = Notifications.notify("Test #{uniq()}")
    assert n.category == "system"
    assert n.read == false
    assert n.title =~ "Test"
  end

  test "notify/2 accepts category and body" do
    {:ok, n} = Notifications.notify("Agent done", category: :agent, body: "Details here")
    assert n.category == "agent"
    assert n.body == "Details here"
  end

  test "notify/2 accepts resource linking" do
    {:ok, n} = Notifications.notify("Job done", category: :job, resource: {"job_run", "42"})
    assert n.resource_type == "job_run"
    assert n.resource_id == "42"
  end

  test "notify/2 normalizes unknown categories to system" do
    {:ok, n} = Notifications.notify("Unknown", category: :banana)
    assert n.category == "system"
  end

  test "list_notifications returns most recent first (higher ID first)" do
    {:ok, n1} = Notifications.notify("First #{uniq()}")
    {:ok, n2} = Notifications.notify("Second #{uniq()}")
    list = Notifications.list_notifications()
    ids = Enum.map(list, & &1.id)
    # n2 has a higher ID and should appear first in descending order
    assert n2.id > n1.id
    assert hd(ids) >= n2.id
  end

  test "unread_count returns count of unread notifications" do
    before = Notifications.unread_count()
    {:ok, _} = Notifications.notify("Unread #{uniq()}")
    assert Notifications.unread_count() == before + 1
  end

  test "mark_read marks a notification as read" do
    {:ok, n} = Notifications.notify("To read #{uniq()}")
    assert n.read == false
    {:ok, updated} = Notifications.mark_read(n.id)
    assert updated.read == true
  end

  test "mark_all_read marks all as read" do
    {:ok, _} = Notifications.notify("A #{uniq()}")
    {:ok, _} = Notifications.notify("B #{uniq()}")
    {:ok, count} = Notifications.mark_all_read()
    assert count >= 2
    assert Notifications.unread_count() == 0
  end

  test "purge_old deletes old notifications" do
    {:ok, n} = Notifications.notify("Old #{uniq()}")

    # Manually backdate the notification
    import Ecto.Query
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-8 * 86_400, :second)

    EyeInTheSky.Repo.update_all(
      from(n in "notifications", where: n.id == ^n.id),
      set: [inserted_at: cutoff]
    )

    {:ok, count} = Notifications.purge_old(7)
    assert count >= 1
  end
end
