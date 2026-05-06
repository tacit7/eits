defmodule EyeInTheSkyWeb.OverviewLive.SkillsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.OverviewLive.Skills, as: SkillsLive
  alias EyeInTheSkyWeb.OverviewLive.Skills.Skill

  defp socket_with(assigns) do
    base = %{
      selected_skill: nil,
      detail_tab: :preview,
      skills: [],
      __changed__: %{}
    }

    %Phoenix.LiveView.Socket{assigns: Map.merge(base, assigns)}
  end

  describe "set_detail_tab event safety" do
    test "accepts 'preview' and sets :preview" do
      {:noreply, socket} =
        SkillsLive.handle_event(
          "set_detail_tab",
          %{"tab" => "preview"},
          socket_with(%{detail_tab: :raw})
        )

      assert socket.assigns.detail_tab == :preview
    end

    test "accepts 'raw' and sets :raw" do
      {:noreply, socket} =
        SkillsLive.handle_event("set_detail_tab", %{"tab" => "raw"}, socket_with(%{}))

      assert socket.assigns.detail_tab == :raw
    end

    test "no-ops on unknown tab values without crashing" do
      socket = socket_with(%{detail_tab: :preview})

      {:noreply, result} =
        SkillsLive.handle_event("set_detail_tab", %{"tab" => "evil_atom_dos_attempt"}, socket)

      assert result.assigns.detail_tab == :preview
    end

    test "no-ops on missing tab key" do
      socket = socket_with(%{detail_tab: :preview})

      {:noreply, result} = SkillsLive.handle_event("set_detail_tab", %{}, socket)

      assert result.assigns.detail_tab == :preview
    end
  end

  describe "select_skill keyed by id (not slug)" do
    test "selects the right skill when two have the same slug but different sources" do
      global = %Skill{
        id: "skills:dup",
        slug: "dup",
        source: :skills,
        description: "global",
        size: 1
      }

      project = %Skill{
        id: "project_skills:dup",
        slug: "dup",
        source: :project_skills,
        description: "project",
        size: 1
      }

      socket = socket_with(%{skills: [global, project]})

      {:noreply, socket} =
        SkillsLive.handle_event("select_skill", %{"id" => "project_skills:dup"}, socket)

      assert socket.assigns.selected_skill.id == "project_skills:dup"
      assert socket.assigns.selected_skill.description == "project"
    end

    test "clicking the same id again deselects" do
      skill = %Skill{id: "skills:foo", slug: "foo", source: :skills, description: "", size: 0}
      socket = socket_with(%{skills: [skill], selected_skill: skill})

      {:noreply, socket} =
        SkillsLive.handle_event("select_skill", %{"id" => "skills:foo"}, socket)

      assert is_nil(socket.assigns.selected_skill)
    end
  end
end
