defmodule EyeInTheSkyWeb.OverviewLive.NotificationsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.OverviewLive.Notifications, as: NotificationsLive

  defp build_socket(assigns \\ %{}) do
    base = %{
      page_title: "Notifications",
      sidebar_tab: :notifications,
      sidebar_project: nil,
      notifications: [],
      filter: "all",
      flash: %{},
      __changed__: %{}
    }

    %Phoenix.LiveView.Socket{
      assigns: Map.merge(base, assigns),
      private: %{live_temp: %{}}
    }
  end

  describe "mount/3" do
    test "initializes socket with correct assigns" do
      socket = build_socket()
      {:ok, result} = NotificationsLive.mount(%{}, %{}, socket)

      assert result.assigns.page_title == "Notifications"
      assert result.assigns.sidebar_tab == :notifications
      assert result.assigns.sidebar_project == nil
      assert result.assigns.filter == "all"
      assert is_list(result.assigns.notifications)
    end
  end

  describe "handle_info/2" do
    test "notification_created reloads notifications list" do
      socket = build_socket(%{notifications: [], filter: "all"})

      {:noreply, result} = NotificationsLive.handle_info({:notification_created, %{}}, socket)

      assert is_list(result.assigns.notifications)
      assert result.assigns.filter == "all"
    end

    test "notification_read reloads notifications list" do
      socket = build_socket(%{notifications: [], filter: "all"})

      {:noreply, result} = NotificationsLive.handle_info({:notification_read, 1}, socket)

      assert is_list(result.assigns.notifications)
    end

    test "notifications_updated reloads notifications list" do
      socket = build_socket(%{notifications: [], filter: "all"})

      {:noreply, result} = NotificationsLive.handle_info({:notifications_updated, nil}, socket)

      assert is_list(result.assigns.notifications)
    end

    test "unmatched info messages return socket unchanged" do
      socket = build_socket(%{filter: "all"})

      {:noreply, result} = NotificationsLive.handle_info({:some_random_event, nil}, socket)

      assert result == socket
    end
  end

  describe "handle_event/3 - mark_read" do
    test "returns noreply for valid integer id" do
      socket = build_socket(%{filter: "all"})

      {tag, _} = NotificationsLive.handle_event("mark_read", %{"id" => "1"}, socket)

      assert tag == :noreply
    end

    test "returns socket unchanged for non-integer id" do
      socket = build_socket(%{filter: "all"})

      {:noreply, result} =
        NotificationsLive.handle_event("mark_read", %{"id" => "not_a_number"}, socket)

      assert result == socket
    end

    test "returns socket unchanged for empty id string" do
      socket = build_socket(%{filter: "all"})

      {:noreply, result} =
        NotificationsLive.handle_event("mark_read", %{"id" => ""}, socket)

      assert result == socket
    end
  end

  describe "handle_event/3 - mark_all_read" do
    test "returns noreply without crashing" do
      socket = build_socket(%{filter: "all"})

      {tag, _} = NotificationsLive.handle_event("mark_all_read", %{}, socket)

      assert tag == :noreply
    end

    test "reloads notifications after marking all read" do
      socket = build_socket(%{filter: "all"})

      {:noreply, result} = NotificationsLive.handle_event("mark_all_read", %{}, socket)

      assert is_list(result.assigns.notifications)
    end
  end

  describe "handle_event/3 - filter" do
    test "sets filter to agent" do
      socket = build_socket(%{filter: "all"})

      {:noreply, result} =
        NotificationsLive.handle_event("filter", %{"category" => "agent"}, socket)

      assert result.assigns.filter == "agent"
    end

    test "sets filter to job" do
      socket = build_socket(%{filter: "all"})

      {:noreply, result} =
        NotificationsLive.handle_event("filter", %{"category" => "job"}, socket)

      assert result.assigns.filter == "job"
    end

    test "sets filter to system" do
      socket = build_socket(%{filter: "all"})

      {:noreply, result} =
        NotificationsLive.handle_event("filter", %{"category" => "system"}, socket)

      assert result.assigns.filter == "system"
    end

    test "resets filter to all" do
      socket = build_socket(%{filter: "agent"})

      {:noreply, result} =
        NotificationsLive.handle_event("filter", %{"category" => "all"}, socket)

      assert result.assigns.filter == "all"
    end

    test "reloads notifications when filter changes" do
      socket = build_socket(%{filter: "all"})

      {:noreply, result} =
        NotificationsLive.handle_event("filter", %{"category" => "job"}, socket)

      assert is_list(result.assigns.notifications)
    end
  end

  describe "handle_event/3 - set_notify_on_stop" do
    test "returns noreply without crashing" do
      socket = build_socket()

      {tag, _} = NotificationsLive.handle_event("set_notify_on_stop", %{}, socket)

      assert tag == :noreply
    end
  end
end
