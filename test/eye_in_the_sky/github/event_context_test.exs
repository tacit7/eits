defmodule EyeInTheSky.Github.EventContextTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Github.EventContext

  describe "from_delivery/2" do
    test "extracts PR fields from pull_request event" do
      payload = %{
        "action" => "opened",
        "pull_request" => %{
          "id" => 456,
          "number" => 42,
          "head" => %{"ref" => "feature/foo"},
          "base" => %{"ref" => "main"},
          "labels" => [%{"name" => "agent-review"}],
          "draft" => false,
          "merged" => false
        },
        "sender" => %{"login" => "urielmaldonado"},
        "repository" => %{"full_name" => "tacit7/eits"}
      }

      delivery = %{
        delivery_id: "abc-123",
        event_type: "pull_request.opened",
        repository_full_name: "tacit7/eits",
        sender_login: "urielmaldonado",
        payload: payload
      }

      ctx = EventContext.from_delivery(delivery)

      assert ctx.delivery_id == "abc-123"
      assert ctx.event_type == "pull_request.opened"
      assert ctx.github_pr_id == 456
      assert ctx.pr_number == 42
      assert ctx.head_branch == "feature/foo"
      assert ctx.base_branch == "main"
      assert ctx.labels == ["agent-review"]
      assert ctx.draft? == false
      assert ctx.merged? == false
    end

    test "extracts head_branch from push event by stripping refs/heads/" do
      payload = %{
        "ref" => "refs/heads/main",
        "sender" => %{"login" => "uriel"},
        "repository" => %{"full_name" => "tacit7/eits"}
      }

      delivery = %{
        delivery_id: "push-1",
        event_type: "push",
        repository_full_name: "tacit7/eits",
        sender_login: "uriel",
        payload: payload
      }

      ctx = EventContext.from_delivery(delivery)
      assert ctx.head_branch == "main"
      assert ctx.base_branch == nil
    end

    test "extracts head_branch from check_run event" do
      payload = %{
        "check_run" => %{
          "check_suite" => %{"head_branch" => "feature/bar"}
        },
        "sender" => %{"login" => "uriel"},
        "repository" => %{"full_name" => "tacit7/eits"}
      }

      delivery = %{
        delivery_id: "cr-1",
        event_type: "check_run.completed",
        repository_full_name: "tacit7/eits",
        sender_login: "uriel",
        payload: payload
      }

      ctx = EventContext.from_delivery(delivery)
      assert ctx.head_branch == "feature/bar"
    end
  end
end
