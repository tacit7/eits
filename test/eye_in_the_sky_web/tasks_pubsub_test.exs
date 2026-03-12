defmodule EyeInTheSkyWeb.TasksPubSubTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  alias EyeInTheSkyWeb.{Projects, Tasks}

  defp uniq, do: System.unique_integer([:positive])

  defp create_project do
    {:ok, project} =
      Projects.create_project(%{
        name: "pubsub-test-#{uniq()}",
        path: "/tmp/pubsub-test-#{uniq()}",
        slug: "pubsub-test-#{uniq()}"
      })

    project
  end

  defp create_task(overrides \\ %{}) do
    {:ok, task} =
      Tasks.create_task(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            title: "Test task #{uniq()}",
            state_id: 1,
            created_at: DateTime.utc_now() |> DateTime.to_iso8601()
          },
          overrides
        )
      )

    task
  end

  describe "create_task/1 broadcasts" do
    test "broadcasts to global tasks topic" do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "tasks")
      create_task()
      assert_receive :tasks_changed, 1000
    end

    test "broadcasts to project-scoped topic when project_id is set" do
      project = create_project()
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "tasks:#{project.id}")
      create_task(%{project_id: project.id})
      assert_receive :tasks_changed, 1000
    end

    test "does not broadcast to another project's topic" do
      project1 = create_project()
      project2 = create_project()
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "tasks:#{project2.id}")
      create_task(%{project_id: project1.id})
      refute_receive :tasks_changed, 200
    end
  end

  describe "update_task/2 broadcasts" do
    test "broadcasts to global tasks topic" do
      task = create_task()
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "tasks")
      Tasks.update_task(task, %{title: "Updated #{uniq()}"})
      assert_receive :tasks_changed, 1000
    end

    test "broadcasts to project-scoped topic when task has project_id" do
      project = create_project()
      task = create_task(%{project_id: project.id})
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "tasks:#{project.id}")
      Tasks.update_task(task, %{title: "Updated #{uniq()}"})
      assert_receive :tasks_changed, 1000
    end

    test "does not broadcast to another project's topic on update" do
      project1 = create_project()
      project2 = create_project()
      task = create_task(%{project_id: project1.id})
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "tasks:#{project2.id}")
      Tasks.update_task(task, %{title: "Updated #{uniq()}"})
      refute_receive :tasks_changed, 200
    end
  end

  describe "delete_task/1 broadcasts" do
    test "broadcasts to global tasks topic" do
      task = create_task()
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "tasks")
      Tasks.delete_task(task)
      assert_receive :tasks_changed, 1000
    end

    test "broadcasts to project-scoped topic when task has project_id" do
      project = create_project()
      task = create_task(%{project_id: project.id})
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "tasks:#{project.id}")
      Tasks.delete_task(task)
      assert_receive :tasks_changed, 1000
    end
  end

  describe "task without project_id" do
    test "only broadcasts to global topic, not any project topic" do
      task = create_task()
      # subscribe to a known project topic and verify no message
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "tasks:99999")
      Tasks.update_task(task, %{title: "No project update #{uniq()}"})
      refute_receive :tasks_changed, 200
    end
  end
end
