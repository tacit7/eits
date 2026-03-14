defmodule EyeInTheSkyWeb.MCP.Tools.NotifyToolTest do
  use EyeInTheSkyWeb.DataCase, async: false

  alias EyeInTheSkyWeb.MCP.Tools.Notify

  @frame :test_frame

  import EyeInTheSkyWeb.Factory

  test "creates a notification with title only" do
    r = Notify.execute(%{title: "Hello"}, @frame) |> json_result()
    assert r.success == true
    assert r.message == "Notification created"
    assert is_integer(r.id)
  end

  test "creates a notification with all fields" do
    r =
      Notify.execute(
        %{
          title: "Job completed",
          body: "Ran successfully",
          category: "job",
          resource_type: "job_run",
          resource_id: "123"
        },
        @frame
      )
      |> json_result()

    assert r.success == true
  end

  test "defaults category to system" do
    r = Notify.execute(%{title: "Default cat"}, @frame) |> json_result()
    assert r.success == true

    notification =
      EyeInTheSkyWeb.Notifications.list_notifications()
      |> Enum.find(&(&1.id == r.id))

    assert notification.category == "system"
  end
end
