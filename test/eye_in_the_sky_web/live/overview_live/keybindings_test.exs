defmodule EyeInTheSkyWeb.OverviewLive.KeybindingsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.OverviewLive.Keybindings, as: KeybindingsLive

  defp build_socket(assigns \\ %{}) do
    base = %{
      page_title: "Keybinding Reference",
      sidebar_tab: :keybindings,
      sidebar_project: nil,
      commands: [],
      flash: %{},
      __changed__: %{}
    }

    %Phoenix.LiveView.Socket{
      assigns: Map.merge(base, assigns),
      private: %{live_temp: %{}}
    }
  end

  describe "mount/3" do
    test "initializes socket with correct assigns" do
      socket = build_socket()
      {:ok, result} = KeybindingsLive.mount(%{}, %{}, socket)

      assert result.assigns.page_title == "Keybinding Reference"
      assert result.assigns.sidebar_tab == :keybindings
      assert result.assigns.sidebar_project == nil
      assert is_list(result.assigns.commands)
      assert length(result.assigns.commands) > 0
    end

    test "commands list contains expected groups" do
      socket = build_socket()
      {:ok, result} = KeybindingsLive.mount(%{}, %{}, socket)

      groups = Enum.map(result.assigns.commands, &Map.get(&1, :group))

      assert "navigation" in groups
      assert "global" in groups
      assert "toggle" in groups
      assert "create" in groups
      assert "context" in groups
    end

    test "navigation 'Go to' group has keybindings" do
      socket = build_socket()
      {:ok, result} = KeybindingsLive.mount(%{}, %{}, socket)

      nav_group =
        Enum.find(result.assigns.commands, fn cmd ->
          cmd.group == "navigation" && cmd.label == "Go to"
        end)

      assert nav_group != nil
      assert is_list(nav_group.bindings)
      assert length(nav_group.bindings) > 0
    end

    test "each command has required fields" do
      socket = build_socket()
      {:ok, result} = KeybindingsLive.mount(%{}, %{}, socket)

      Enum.each(result.assigns.commands, fn cmd ->
        assert Map.has_key?(cmd, :group)
        assert Map.has_key?(cmd, :label)
        assert Map.has_key?(cmd, :bindings)
        assert is_list(cmd.bindings)

        Enum.each(cmd.bindings, fn binding ->
          assert Map.has_key?(binding, :keys)
          assert Map.has_key?(binding, :desc)
          assert is_list(binding.keys)
          assert is_binary(binding.desc)
        end)
      end)
    end
  end

  describe "handle_event/3 - set_notify_on_stop" do
    test "returns noreply without crashing" do
      socket = build_socket()

      {tag, _result} = KeybindingsLive.handle_event("set_notify_on_stop", %{}, socket)

      assert tag == :noreply
    end
  end

  describe "keybindings completeness" do
    test "sessions page keybindings include archive and delete" do
      socket = build_socket()
      {:ok, result} = KeybindingsLive.mount(%{}, %{}, socket)

      sessions_group =
        Enum.find(result.assigns.commands, fn cmd ->
          cmd.group == "context" && cmd.label == "Sessions page"
        end)

      assert sessions_group != nil
      descs = Enum.map(sessions_group.bindings, &Map.get(&1, :desc))
      assert "Archive focused session" in descs
      assert "Delete focused session" in descs
    end

    test "leader prefix groups have Space-prefixed keybindings" do
      socket = build_socket()
      {:ok, result} = KeybindingsLive.mount(%{}, %{}, socket)

      leader_groups =
        Enum.filter(result.assigns.commands, fn cmd ->
          cmd.group == "navigation" && String.starts_with?(cmd.label, "Leader")
        end)

      assert length(leader_groups) > 0

      has_space_keys =
        Enum.any?(leader_groups, fn group ->
          Enum.any?(group.bindings, fn binding -> "Space" in binding.keys end)
        end)

      assert has_space_keys
    end

    test "create group has new agent, task, and note keybindings" do
      socket = build_socket()
      {:ok, result} = KeybindingsLive.mount(%{}, %{}, socket)

      create_group = Enum.find(result.assigns.commands, fn cmd -> cmd.label == "Create" end)

      assert create_group != nil
      descs = Enum.map(create_group.bindings, &Map.get(&1, :desc))
      assert "New agent" in descs
      assert "New task" in descs
      assert "New note" in descs
    end

    test "global group contains command palette and back/forward bindings" do
      socket = build_socket()
      {:ok, result} = KeybindingsLive.mount(%{}, %{}, socket)

      global_group = Enum.find(result.assigns.commands, fn cmd -> cmd.group == "global" end)

      assert global_group != nil
      descs = Enum.map(global_group.bindings, &Map.get(&1, :desc))
      assert Enum.any?(descs, &String.contains?(&1, "palette"))
      assert Enum.any?(descs, &String.contains?(&1, "back"))
    end
  end
end
