defmodule EyeInTheSkyWeb.Controllers.Api.V1.IamUserPromptSubmitTest do
  use EyeInTheSkyWeb.ConnCase

  alias EyeInTheSky.IAM.Evaluator
  alias EyeInTheSky.IAM.HookResponse
  alias EyeInTheSky.IAM.Normalizer
  alias EyeInTheSky.IAM.Policy
  alias EyeInTheSky.Repo

  setup do
    # Build the policy in memory (not inserted) — PolicyCache runs in a GenServer
    # that cannot see sandbox transactions, so we pass policies directly to Evaluator.decide.
    policy = %Policy{
      id: System.unique_integer([:positive]),
      system_key: "test.sanitize_prompt_api_keys",
      name: "Test sanitize prompt API keys",
      effect: "instruct",
      action: "*",
      agent_type: "*",
      event: "UserPromptSubmit",
      builtin_matcher: "sanitize_prompt_api_keys",
      priority: 100,
      enabled: true,
      message: "Prompt has been scanned and secrets redacted.",
      editable_fields: ["enabled"]
    }

    {:ok, policy: policy}
  end

  describe "UserPromptSubmit hook evaluation" do
    test "redacts secrets from prompt via sanitize_prompt_api_keys", %{policy: policy} do
      payload = %{
        "hook_event_name" => "UserPromptSubmit",
        "prompt" => "Please use this API key: sk-ant-abcdefghij1234567890"
      }

      ctx = Normalizer.from_hook_payload(payload)
      decision = Evaluator.decide(ctx, policies: [policy])
      response = HookResponse.from_decision(decision, ctx.event)

      # Should allow (permission: allow)
      assert decision.permission == :allow

      # Should have instruction from sanitize_prompt_api_keys
      assert decision.instructions != []
      assert Enum.any?(decision.instructions, fn i ->
        String.contains?(i.message, "Redacted:")
      end)

      # Check response structure — UserPromptSubmit must replace the prompt, not append context
      assert response["suppressUserPrompt"] == true
      assert response["hookSpecificOutput"]["hookEventName"] == "UserPromptSubmit"
      assert response["hookSpecificOutput"]["userPrompt"] != nil
      assert String.contains?(response["hookSpecificOutput"]["userPrompt"], "[REDACTED:anthropic]")
    end

    test "passes through benign prompts without redaction instructions", %{policy: policy} do
      payload = %{
        "hook_event_name" => "UserPromptSubmit",
        "prompt" => "What is the capital of France?"
      }

      ctx = Normalizer.from_hook_payload(payload)
      decision = Evaluator.decide(ctx, policies: [policy])

      assert decision.permission == :allow

      # Benign prompt should have no redaction instructions
      redaction_instruction = Enum.find(decision.instructions, fn i ->
        String.contains?(i.message, "Redacted:")
      end)

      assert redaction_instruction == nil
    end

    test "hook response includes correct structure for UserPromptSubmit with redaction", %{
      policy: policy
    } do
      payload = %{
        "hook_event_name" => "UserPromptSubmit",
        "prompt" => "key is AKIAIOSFODNN7EXAMPLE"
      }

      ctx = Normalizer.from_hook_payload(payload)
      decision = Evaluator.decide(ctx, policies: [policy])
      response = HookResponse.from_decision(decision, ctx.event)

      # UserPromptSubmit replaces prompt via suppressUserPrompt + userPrompt, not additionalContext
      assert response["suppressUserPrompt"] == true
      assert response["hookSpecificOutput"]["hookEventName"] == "UserPromptSubmit"
      assert response["hookSpecificOutput"]["userPrompt"] != nil
      assert String.contains?(response["hookSpecificOutput"]["userPrompt"], "[REDACTED:aws]")
    end

    test "normalizer extracts prompt from UserPromptSubmit payload" do
      payload = %{
        "hook_event_name" => "UserPromptSubmit",
        "prompt" => "test prompt"
      }

      ctx = Normalizer.from_hook_payload(payload)

      assert ctx.event == :user_prompt_submit
      assert ctx.prompt == "test prompt"
    end
  end
end
