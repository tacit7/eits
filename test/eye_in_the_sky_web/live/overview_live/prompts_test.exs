defmodule EyeInTheSkyWeb.OverviewLive.PromptsTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSkyWeb.OverviewLive.Prompts, as: PromptsLive

  defp build_socket(assigns \\ %{}) do
    base = %{
      prompts: [],
      filtered_prompts: [],
      selected_prompt: nil,
      search_query: "",
      sort_by: "recent",
      scope_filter: "all",
      detail_tab: :preview,
      page_title: "Prompts",
      sidebar_tab: :prompts,
      sidebar_project: nil,
      flash: %{},
      __changed__: %{}
    }

    %Phoenix.LiveView.Socket{
      assigns: Map.merge(base, assigns),
      private: %{live_temp: %{}}
    }
  end

  defp prompt(opts \\ []) do
    %{
      id: Keyword.get(opts, :id, 1),
      slug: Keyword.get(opts, :slug, "test-prompt"),
      version: Keyword.get(opts, :version, 1),
      description: Keyword.get(opts, :description, "Test prompt"),
      prompt_text: Keyword.get(opts, :prompt_text, "Test prompt text"),
      project_id: Keyword.get(opts, :project_id, nil)
    }
  end

  describe "mount/3" do
    test "initializes socket with correct assigns" do
      socket = build_socket()
      {:ok, result} = PromptsLive.mount(%{}, %{}, socket)

      assert result.assigns.page_title == "Prompts"
      assert result.assigns.search_query == ""
      assert result.assigns.sort_by == "recent"
      assert result.assigns.scope_filter == "all"
      assert result.assigns.selected_prompt == nil
      assert result.assigns.detail_tab == :preview
    end
  end

  describe "handle_params/3" do
    test "selects prompt by id from params" do
      p = prompt(id: 42, slug: "test")
      socket = build_socket(%{prompts: [p]})

      {:noreply, result} = PromptsLive.handle_params(%{"id" => "42"}, "", socket)

      assert result.assigns.selected_prompt == p
    end

    test "converts string id to integer for lookup" do
      p1 = prompt(id: 10, slug: "prompt-10")
      p2 = prompt(id: 20, slug: "prompt-20")
      socket = build_socket(%{prompts: [p1, p2]})

      {:noreply, result} = PromptsLive.handle_params(%{"id" => "20"}, "", socket)

      assert result.assigns.selected_prompt == p2
    end

    test "sets selected_prompt to nil when id not found" do
      p = prompt(id: 1)
      socket = build_socket(%{prompts: [p]})

      {:noreply, result} = PromptsLive.handle_params(%{"id" => "999"}, "", socket)

      assert is_nil(result.assigns.selected_prompt)
    end

    test "handles empty params without crashing" do
      socket = build_socket()

      {:noreply, result} = PromptsLive.handle_params(%{}, "", socket)

      assert is_nil(result.assigns.selected_prompt)
    end
  end

  describe "handle_event/3 - search" do
    test "updates search_query" do
      socket = build_socket(%{search_query: ""})

      {:noreply, result} = PromptsLive.handle_event("search", %{"query" => "test"}, socket)

      assert result.assigns.search_query == "test"
    end

    test "handles empty search query" do
      socket = build_socket(%{search_query: "prev"})

      {:noreply, result} = PromptsLive.handle_event("search", %{"query" => ""}, socket)

      assert result.assigns.search_query == ""
    end
  end

  describe "handle_event/3 - sort_prompts" do
    test "updates sort_by to name_asc" do
      socket = build_socket(%{sort_by: "recent"})

      {:noreply, result} = PromptsLive.handle_event("sort_prompts", %{"by" => "name_asc"}, socket)

      assert result.assigns.sort_by == "name_asc"
    end

    test "updates sort_by to name_desc" do
      socket = build_socket(%{sort_by: "recent"})

      {:noreply, result} =
        PromptsLive.handle_event("sort_prompts", %{"by" => "name_desc"}, socket)

      assert result.assigns.sort_by == "name_desc"
    end

    test "updates sort_by to recent" do
      socket = build_socket(%{sort_by: "name_asc"})

      {:noreply, result} = PromptsLive.handle_event("sort_prompts", %{"by" => "recent"}, socket)

      assert result.assigns.sort_by == "recent"
    end
  end

  describe "handle_event/3 - filter_scope" do
    test "updates scope_filter to global" do
      socket = build_socket(%{scope_filter: "all"})

      {:noreply, result} =
        PromptsLive.handle_event("filter_scope", %{"scope" => "global"}, socket)

      assert result.assigns.scope_filter == "global"
    end

    test "updates scope_filter to project" do
      socket = build_socket(%{scope_filter: "all"})

      {:noreply, result} =
        PromptsLive.handle_event("filter_scope", %{"scope" => "project"}, socket)

      assert result.assigns.scope_filter == "project"
    end

    test "updates scope_filter to all" do
      socket = build_socket(%{scope_filter: "global"})

      {:noreply, result} = PromptsLive.handle_event("filter_scope", %{"scope" => "all"}, socket)

      assert result.assigns.scope_filter == "all"
    end
  end

  describe "handle_event/3 - select_prompt" do
    test "selects a prompt by string id" do
      p = prompt(id: 1)
      socket = build_socket(%{prompts: [p], selected_prompt: nil})

      {:noreply, result} = PromptsLive.handle_event("select_prompt", %{"id" => "1"}, socket)

      assert result.assigns.selected_prompt == p
    end

    test "selects a prompt with a multi-digit id" do
      p = prompt(id: 42)
      socket = build_socket(%{prompts: [p], selected_prompt: nil})

      {:noreply, result} = PromptsLive.handle_event("select_prompt", %{"id" => "42"}, socket)

      assert result.assigns.selected_prompt == p
    end

    test "deselects when clicking the same prompt" do
      p = prompt(id: 1)
      socket = build_socket(%{prompts: [p], selected_prompt: p})

      {:noreply, result} = PromptsLive.handle_event("select_prompt", %{"id" => "1"}, socket)

      assert is_nil(result.assigns.selected_prompt)
    end

    test "switches to a different prompt" do
      p1 = prompt(id: 1, slug: "first")
      p2 = prompt(id: 2, slug: "second")
      socket = build_socket(%{prompts: [p1, p2], selected_prompt: p1})

      {:noreply, result} = PromptsLive.handle_event("select_prompt", %{"id" => "2"}, socket)

      assert result.assigns.selected_prompt == p2
    end

    test "resets detail_tab to preview when selecting" do
      p = prompt(id: 1)
      socket = build_socket(%{prompts: [p], selected_prompt: nil, detail_tab: :raw})

      {:noreply, result} = PromptsLive.handle_event("select_prompt", %{"id" => "1"}, socket)

      assert result.assigns.detail_tab == :preview
    end
  end

  describe "handle_event/3 - close_viewer" do
    test "clears selected_prompt" do
      p = prompt(id: 1)
      socket = build_socket(%{prompts: [p], selected_prompt: p})

      {:noreply, result} = PromptsLive.handle_event("close_viewer", %{}, socket)

      assert is_nil(result.assigns.selected_prompt)
    end
  end

  describe "handle_event/3 - set_detail_tab" do
    test "accepts 'preview' and sets :preview" do
      socket = build_socket(%{detail_tab: :raw})

      {:noreply, result} =
        PromptsLive.handle_event("set_detail_tab", %{"tab" => "preview"}, socket)

      assert result.assigns.detail_tab == :preview
    end

    test "accepts 'raw' and sets :raw" do
      socket = build_socket(%{detail_tab: :preview})

      {:noreply, result} = PromptsLive.handle_event("set_detail_tab", %{"tab" => "raw"}, socket)

      assert result.assigns.detail_tab == :raw
    end

    test "ignores unknown tab values" do
      socket = build_socket(%{detail_tab: :preview})

      {:noreply, result} =
        PromptsLive.handle_event("set_detail_tab", %{"tab" => "evil_tab"}, socket)

      assert result.assigns.detail_tab == :preview
    end

    test "ignores missing tab key" do
      socket = build_socket(%{detail_tab: :preview})

      {:noreply, result} = PromptsLive.handle_event("set_detail_tab", %{}, socket)

      assert result.assigns.detail_tab == :preview
    end
  end

  describe "handle_event/3 - set_notify_on_stop" do
    test "returns noreply without crashing" do
      socket = build_socket()

      {tag, _} = PromptsLive.handle_event("set_notify_on_stop", %{}, socket)

      assert tag == :noreply
    end
  end
end
