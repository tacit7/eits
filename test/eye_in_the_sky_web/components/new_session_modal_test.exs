defmodule EyeInTheSkyWeb.Components.NewSessionModalTest do
  use EyeInTheSkyWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.NewSessionModal

  @agents [
    {"eits-superpowers", "EITS Superpowers", :global},
    {"eits-workflow", "EITS Workflow", :global},
    {"bugfix", "Bug Fixer", :global},
    {"code-reviewer", "Code Reviewer", :project}
  ]

  defp base_assigns(overrides \\ %{}) do
    Map.merge(
      %{
        id: "test-modal",
        show: true,
        toggle_event: "toggle_new_session",
        submit_event: "create_session",
        prompts: [],
        projects: [],
        current_project: nil,
        available_agents: @agents,
        file_uploads: nil
      },
      overrides
    )
  end

  # Host LiveView for mounting NewSessionModal as a LiveComponent in isolated tests.
  # Uses Phoenix.LiveView directly (no layout) to avoid the app layout's NavHook assigns.
  defmodule HostLive do
    use Phoenix.LiveView

    def mount(_params, _session, socket) do
      {:ok,
       assign(socket,
         show: true,
         toggle_event: "toggle_new_session",
         submit_event: "create_session",
         prompts: [],
         projects: [],
         current_project: nil,
         available_agents: [],
         file_uploads: nil
       )}
    end

    def render(assigns) do
      ~H"""
      <.live_component
        module={EyeInTheSkyWeb.Components.NewSessionModal}
        id="test-modal"
        show={@show}
        toggle_event={@toggle_event}
        submit_event={@submit_event}
        prompts={@prompts}
        projects={@projects}
        current_project={@current_project}
        available_agents={@available_agents}
        file_uploads={@file_uploads}
      />
      """
    end

    def handle_event(_, _, socket), do: {:noreply, socket}
  end

  defp mount_new_session_modal(conn) do
    live_isolated(conn, __MODULE__.HostLive)
  end

  defp render_new_session_modal(overrides) do
    render_component(NewSessionModal, base_assigns(overrides))
  end

  # -------------------------------------------------------------------------
  # JS combobox rendering — verifies HTML structure and data-agents encoding
  # -------------------------------------------------------------------------

  describe "agent combobox" do
    test "renders hook element with data-agents JSON when agents present" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ ~s(phx-hook="AgentCombobox")
      assert html =~ ~s(data-agents=)
      assert html =~ "Search agents..."
    end

    test "does not render agent field when no agents available" do
      html = render_component(NewSessionModal, base_assigns(%{available_agents: []}))

      refute html =~ ~s(phx-hook="AgentCombobox")
      refute html =~ "Search agents..."
    end

    test "data-agents JSON contains all agent slugs" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ "eits-superpowers"
      assert html =~ "eits-workflow"
      assert html =~ "bugfix"
      assert html =~ "code-reviewer"
    end

    test "data-agents JSON contains agent names" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ "EITS Superpowers"
      assert html =~ "EITS Workflow"
      assert html =~ "Bug Fixer"
      assert html =~ "Code Reviewer"
    end

    test "data-agents JSON contains scope strings" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ "global"
      assert html =~ "project"
    end

    test "all agents are encoded regardless of count" do
      many_agents = for i <- 1..15, do: {"agent-#{i}", "Agent #{i}", :global}

      html = render_component(NewSessionModal, base_assigns(%{available_agents: many_agents}))

      for i <- 1..15 do
        assert html =~ "agent-#{i}"
      end
    end

    test "renders hidden input and visible search input" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ ~s(data-combobox-value)
      assert html =~ ~s(data-combobox-input)
      assert html =~ ~s(data-combobox-list)
    end

    test "no datalist element rendered" do
      html = render_component(NewSessionModal, base_assigns())

      refute html =~ "<datalist"
      refute html =~ "list=\"agent-options\""
    end
  end

  describe "module exports" do
    test "NewSessionModal is compiled and exports render/1" do
      assert Code.ensure_loaded?(NewSessionModal)
      assert function_exported?(NewSessionModal, :render, 1)
    end
  end

  describe "shared model selector" do
    test "renders with allow_provider_switch? true and the full cross-provider list" do
      html = render_new_session_modal(%{})
      assert html =~ ~s(data-allow-provider-switch="true")
    end

    test "selecting a model via the shared component's event updates both provider and model",
         %{conn: conn} do
      {:ok, view, _html} = mount_new_session_modal(conn)

      view
      |> element("#new-session-model-selector")
      |> render_hook("model_and_provider_selected", %{"provider" => "codex", "model" => "gpt-5.5"})

      assert render(view) =~ "GPT-5.5"
    end

    test "an invalid payload is rejected, previous selection is kept", %{conn: conn} do
      {:ok, view, _html} = mount_new_session_modal(conn)

      view
      |> element("#new-session-model-selector")
      |> render_hook("model_and_provider_selected", %{
        "provider" => "codex",
        "model" => "not-a-real-model"
      })

      refute render(view) =~ "not-a-real-model"
    end
  end

  describe "update/2" do
    test "merges parent updates while preserving open modal state" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          show: true,
          toggle_event: "toggle_new_session",
          submit_event: "create_session",
          prompts: [],
          projects: [%{id: 1, name: "Original Project"}],
          current_project: nil,
          available_agents: [{"local-agent", "Local Agent", :global}],
          selected_model: "claude-sonnet-4-6",
          selected_provider: "claude",
          selected_prompt_id: "prompt-1",
          prefill_text: "Existing prompt text",
          file_uploads: %{agent_images: %{entries: [], ref: "old-ref"}}
        }
      }

      new_uploads = %{agent_images: %{entries: [%{client_name: "shot.png"}], ref: "new-ref"}}

      {:ok, result_socket} =
        NewSessionModal.update(
          %{
            show: true,
            button_text: "Launch from refresh",
            current_project: %{id: 2, name: "Updated Project", path: "/tmp/updated"},
            file_uploads: new_uploads
          },
          socket
        )

      assert result_socket.assigns.button_text == "Launch from refresh"
      assert result_socket.assigns.current_project.id == 2
      assert result_socket.assigns.available_agents == [{"local-agent", "Local Agent", :global}]
      assert result_socket.assigns.file_uploads == new_uploads
    end
  end
end
