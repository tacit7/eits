defmodule EyeInTheSky.Checks.HEExWhitespacePreInlineTest do
  use Credo.Test.Case, async: true

  alias EyeInTheSky.Checks.HEExWhitespacePreInline

  setup_all do
    {:ok, _} = Application.ensure_all_started(:credo)
    :ok
  end

  test "flags whitespace-pre-wrap content rendered on the next line" do
    """
    defmodule Sample do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <div class="whitespace-pre-wrap">
          {String.trim(@task.description)}
        </div>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(HEExWhitespacePreInline)
    |> assert_issue(fn issue ->
      assert issue.line_no == 6
      assert issue.message =~ "template-indentation whitespace"
    end)
  end

  test "allows whitespace-pre-wrap content rendered inline" do
    """
    defmodule Sample do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <div class="whitespace-pre-wrap">{String.trim(@task.description)}</div>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(HEExWhitespacePreInline)
    |> refute_issues()
  end
end
