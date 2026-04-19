defmodule EyeInTheSky.IAM.NormalizerTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Normalizer

  describe "from_hook_payload/1 — event normalization" do
    test "maps PreToolUse string to :pre_tool_use" do
      ctx = Normalizer.from_hook_payload(%{"hook_event_name" => "PreToolUse"})
      assert ctx.event == :pre_tool_use
    end

    test "maps PostToolUse string to :post_tool_use" do
      ctx = Normalizer.from_hook_payload(%{"hook_event_name" => "PostToolUse"})
      assert ctx.event == :post_tool_use
    end

    test "maps Stop string to :stop" do
      ctx = Normalizer.from_hook_payload(%{"hook_event_name" => "Stop"})
      assert ctx.event == :stop
    end

    test "defaults unknown event to :pre_tool_use" do
      ctx = Normalizer.from_hook_payload(%{"hook_event_name" => "Surprise"})
      assert ctx.event == :pre_tool_use
    end
  end

  describe "from_hook_payload/1 — agent_type" do
    test "uses subagent_type when present" do
      ctx = Normalizer.from_hook_payload(%{"subagent_type" => "worker-agent"})
      assert ctx.agent_type == "worker-agent"
    end

    test "falls back to root when no agent key set" do
      ctx = Normalizer.from_hook_payload(%{})
      assert ctx.agent_type == "root"
    end

    test "prefers agent_type over subagent_type when both set" do
      ctx =
        Normalizer.from_hook_payload(%{
          "agent_type" => "code-reviewer",
          "subagent_type" => "worker-agent"
        })

      assert ctx.agent_type == "code-reviewer"
    end
  end

  describe "from_hook_payload/1 — Bash resource extraction" do
    test "pulls command into resource_path and resource_content" do
      ctx =
        Normalizer.from_hook_payload(%{
          "tool_name" => "Bash",
          "tool_input" => %{"command" => "rm -rf /"}
        })

      assert ctx.tool == "Bash"
      assert ctx.resource_type == :command
      assert ctx.resource_path == "rm -rf /"
      assert ctx.resource_content == "rm -rf /"
    end
  end

  describe "from_hook_payload/1 — Edit/Write resource extraction" do
    test "Edit pulls file_path + new_string" do
      ctx =
        Normalizer.from_hook_payload(%{
          "tool_name" => "Edit",
          "tool_input" => %{
            "file_path" => "/tmp/foo.ex",
            "new_string" => "defmodule Foo"
          }
        })

      assert ctx.resource_type == :file
      assert ctx.resource_path == "/tmp/foo.ex"
      assert ctx.resource_content == "defmodule Foo"
    end

    test "Write pulls file_path + content" do
      ctx =
        Normalizer.from_hook_payload(%{
          "tool_name" => "Write",
          "tool_input" => %{"file_path" => "/tmp/bar.txt", "content" => "hello"}
        })

      assert ctx.resource_type == :file
      assert ctx.resource_path == "/tmp/bar.txt"
      assert ctx.resource_content == "hello"
    end

    test "MultiEdit concatenates new_string fragments" do
      ctx =
        Normalizer.from_hook_payload(%{
          "tool_name" => "MultiEdit",
          "tool_input" => %{
            "file_path" => "/tmp/baz.ex",
            "edits" => [
              %{"new_string" => "a"},
              %{"new_string" => "b"}
            ]
          }
        })

      assert ctx.resource_type == :file
      assert ctx.resource_path == "/tmp/baz.ex"
      assert ctx.resource_content == "a\nb"
    end
  end

  describe "from_hook_payload/1 — unknown tools" do
    test "fall through with :unknown resource_type" do
      ctx =
        Normalizer.from_hook_payload(%{
          "tool_name" => "MysteryTool",
          "tool_input" => %{"something" => "else"}
        })

      assert ctx.resource_type == :unknown
      assert ctx.resource_path == nil
    end

    test "empty payload yields a valid context" do
      ctx = Normalizer.from_hook_payload(%{})
      assert %Context{} = ctx
      assert ctx.tool == nil
      assert ctx.resource_type == :unknown
    end
  end

  describe "from_hook_payload/1 — raw_tool_input preserved" do
    test "echoes raw_tool_input for downstream built-ins" do
      input = %{"command" => "echo hi", "timeout" => 5_000}

      ctx =
        Normalizer.from_hook_payload(%{
          "tool_name" => "Bash",
          "tool_input" => input
        })

      assert ctx.raw_tool_input == input
    end
  end
end
