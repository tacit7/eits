defmodule EyeInTheSky.Claude.JobTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.{ContentBlock, Job}

  describe "new/2" do
    test "creates job with empty content_blocks by default" do
      job = Job.new("hello", %{has_messages: false})
      assert job.message == "hello"
      assert job.content_blocks == []
      assert job.context == %{has_messages: false}
      assert %DateTime{} = job.submitted_at
    end
  end

  describe "new/3" do
    test "creates job with content_blocks" do
      blocks = [ContentBlock.new_image("abc", "image/png")]
      job = Job.new("describe this", %{has_messages: false}, blocks)

      assert job.message == "describe this"
      assert length(job.content_blocks) == 1
      assert [%ContentBlock.Image{data: "abc", mime_type: "image/png"}] = job.content_blocks
    end

    test "accepts empty content_blocks list" do
      job = Job.new("hello", %{has_messages: false}, [])
      assert job.content_blocks == []
    end
  end

  describe "assign_id/1" do
    test "assigns a positive integer id" do
      job = Job.new("test", %{has_messages: false}) |> Job.assign_id()
      assert is_integer(job.id) and job.id > 0
    end
  end

  describe "as_fresh_session/1" do
    test "sets has_messages to false" do
      job = Job.new("test", %{has_messages: true})
      fresh = Job.as_fresh_session(job)
      assert fresh.context.has_messages == false
    end
  end
end
