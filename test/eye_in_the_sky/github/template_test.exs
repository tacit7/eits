defmodule EyeInTheSky.Github.TemplateTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Github.Template

  @ctx %{
    "repository" => "tacit7/eits",
    "event_type" => "pull_request.opened",
    "sender_login" => "uriel",
    "pr_number" => 42,
    "pr_title" => "Fix the thing",
    "pr_url" => "https://github.com/tacit7/eits/pull/42",
    "head_branch" => "feature/foo",
    "base_branch" => "main"
  }

  describe "render/2" do
    test "replaces known variables" do
      assert {:ok, "Review PR 42 in tacit7/eits"} =
               Template.render("Review PR {{pr_number}} in {{repository}}", @ctx)
    end

    test "returns error for unknown variable" do
      assert {:error, "unknown template variable: secret_token"} =
               Template.render("{{secret_token}}", @ctx)
    end

    test "renders string with no variables unchanged" do
      assert {:ok, "no variables here"} = Template.render("no variables here", @ctx)
    end
  end

  describe "validate/1" do
    test "returns :ok for template with only known variables" do
      assert :ok = Template.validate("Review PR {{pr_number}} in {{repository}}")
    end

    test "returns error for unknown variable at validate time" do
      assert {:error, _} = Template.validate("{{unknown_var}}")
    end
  end
end
