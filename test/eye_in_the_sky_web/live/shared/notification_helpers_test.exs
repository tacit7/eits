defmodule EyeInTheSkyWeb.Live.Shared.NotificationHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers

  # Build a minimal socket-shaped map — NotificationHelpers only calls
  # Phoenix.Component.assign/3, which works on any map that has :assigns.
  defp socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{assigns: Map.merge(%{__changed__: %{}}, assigns)}
  end

  describe "set_notify_on_stop/2 — with enabled param" do
    test "assigns true when enabled is boolean true" do
      result = NotificationHelpers.set_notify_on_stop(socket(), %{"enabled" => true})
      assert result.assigns.notify_on_stop == true
    end

    test "assigns true when enabled is the string \"true\"" do
      result = NotificationHelpers.set_notify_on_stop(socket(), %{"enabled" => "true"})
      assert result.assigns.notify_on_stop == true
    end

    test "assigns true when enabled is \"on\"" do
      result = NotificationHelpers.set_notify_on_stop(socket(), %{"enabled" => "on"})
      assert result.assigns.notify_on_stop == true
    end

    test "assigns true when enabled is integer 1" do
      result = NotificationHelpers.set_notify_on_stop(socket(), %{"enabled" => 1})
      assert result.assigns.notify_on_stop == true
    end

    test "assigns true when enabled is the string \"1\"" do
      result = NotificationHelpers.set_notify_on_stop(socket(), %{"enabled" => "1"})
      assert result.assigns.notify_on_stop == true
    end

    test "assigns false when enabled is boolean false" do
      result = NotificationHelpers.set_notify_on_stop(socket(), %{"enabled" => false})
      assert result.assigns.notify_on_stop == false
    end

    test "assigns false when enabled is \"false\"" do
      result = NotificationHelpers.set_notify_on_stop(socket(), %{"enabled" => "false"})
      assert result.assigns.notify_on_stop == false
    end

    test "assigns false when enabled is \"off\"" do
      result = NotificationHelpers.set_notify_on_stop(socket(), %{"enabled" => "off"})
      assert result.assigns.notify_on_stop == false
    end

    test "assigns false when enabled is integer 0" do
      result = NotificationHelpers.set_notify_on_stop(socket(), %{"enabled" => 0})
      assert result.assigns.notify_on_stop == false
    end

    test "assigns false when enabled is \"0\"" do
      result = NotificationHelpers.set_notify_on_stop(socket(), %{"enabled" => "0"})
      assert result.assigns.notify_on_stop == false
    end
  end

  describe "set_notify_on_stop/2 — missing enabled param" do
    test "returns socket unchanged when params is an empty map" do
      original = socket(%{notify_on_stop: true})
      result = NotificationHelpers.set_notify_on_stop(original, %{})
      assert result == original
    end

    test "returns socket unchanged when params has unrelated keys" do
      original = socket(%{notify_on_stop: false})
      result = NotificationHelpers.set_notify_on_stop(original, %{"something_else" => "value"})
      assert result == original
    end

    test "returns socket unchanged when params is nil" do
      original = socket()
      result = NotificationHelpers.set_notify_on_stop(original, nil)
      assert result == original
    end
  end
end
