defmodule EyeInTheSkyWeb.Components.Rail.FilterActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSkyWeb.Components.Rail.Loader

  def handle_set_session_sort(%{"sort" => sort_str}, socket) do
    sort = Loader.parse_session_sort(sort_str)

    sessions =
      Loader.load_flyout_sessions(
        socket.assigns.sidebar_project,
        sort,
        socket.assigns.session_name_filter,
        socket.assigns.session_show
      )

    {:noreply, socket |> assign(:session_sort, sort) |> assign(:flyout_sessions, sessions)}
  end

  def handle_update_session_name_filter(%{"value" => value}, socket) do
    sessions =
      Loader.load_flyout_sessions(
        socket.assigns.sidebar_project,
        socket.assigns.session_sort,
        value,
        socket.assigns.session_show
      )

    {:noreply, socket |> assign(:session_name_filter, value) |> assign(:flyout_sessions, sessions)}
  end

  def handle_set_session_show(%{"show" => show_str}, socket) do
    show = Loader.parse_session_show(show_str)

    sessions =
      Loader.load_flyout_sessions(
        socket.assigns.sidebar_project,
        socket.assigns.session_sort,
        socket.assigns.session_name_filter,
        show
      )

    {:noreply, socket |> assign(:session_show, show) |> assign(:flyout_sessions, sessions)}
  end

  def handle_update_task_search(%{"value" => value}, socket) do
    tasks =
      Loader.load_flyout_tasks(
        socket.assigns.sidebar_project,
        value,
        socket.assigns.task_state_filter
      )

    {:noreply, socket |> assign(:task_search, value) |> assign(:flyout_tasks, tasks)}
  end

  def handle_set_task_state_filter(%{"state" => state_str}, socket) do
    state_id = Loader.parse_task_state(state_str)

    tasks =
      Loader.load_flyout_tasks(
        socket.assigns.sidebar_project,
        socket.assigns.task_search,
        state_id
      )

    {:noreply, socket |> assign(:task_state_filter, state_id) |> assign(:flyout_tasks, tasks)}
  end

  def handle_update_note_search(%{"value" => value}, socket) do
    notes =
      Loader.load_flyout_notes(
        socket.assigns.sidebar_project,
        value,
        socket.assigns.note_parent_type
      )

    {:noreply, socket |> assign(:note_search, value) |> assign(:flyout_notes, notes)}
  end

  def handle_set_note_parent_type(%{"type" => type_str}, socket) do
    parent_type = if type_str == "all", do: nil, else: type_str

    notes =
      Loader.load_flyout_notes(
        socket.assigns.sidebar_project,
        socket.assigns.note_search,
        parent_type
      )

    {:noreply, socket |> assign(:note_parent_type, parent_type) |> assign(:flyout_notes, notes)}
  end

  def handle_update_agent_search(%{"value" => value}, socket) do
    agents =
      Loader.load_flyout_agents_filtered(
        socket.assigns.sidebar_project,
        value,
        socket.assigns.agent_scope
      )

    {:noreply, socket |> assign(:agent_search, value) |> assign(:flyout_agents, agents)}
  end

  def handle_set_agent_scope(%{"scope" => scope}, socket) do
    agents =
      Loader.load_flyout_agents_filtered(
        socket.assigns.sidebar_project,
        socket.assigns.agent_search,
        scope
      )

    {:noreply, socket |> assign(:agent_scope, scope) |> assign(:flyout_agents, agents)}
  end

  def handle_update_skill_search(%{"value" => value}, socket) do
    skills =
      Loader.load_flyout_skills_filtered(
        socket.assigns.sidebar_project,
        value,
        socket.assigns.skill_scope
      )

    {:noreply, socket |> assign(:skill_search, value) |> assign(:flyout_skills, skills)}
  end

  def handle_set_skill_scope(%{"scope" => scope}, socket) do
    skills =
      Loader.load_flyout_skills_filtered(
        socket.assigns.sidebar_project,
        socket.assigns.skill_search,
        scope
      )

    {:noreply, socket |> assign(:skill_scope, scope) |> assign(:flyout_skills, skills)}
  end

  def handle_update_prompt_search(%{"value" => value}, socket) do
    prompts =
      Loader.load_flyout_prompts(
        socket.assigns.sidebar_project,
        value,
        socket.assigns.prompt_scope
      )

    {:noreply, socket |> assign(:prompt_search, value) |> assign(:flyout_prompts, prompts)}
  end

  def handle_set_prompt_scope(%{"scope" => scope}, socket) do
    prompts =
      Loader.load_flyout_prompts(
        socket.assigns.sidebar_project,
        socket.assigns.prompt_search,
        scope
      )

    {:noreply, socket |> assign(:prompt_scope, scope) |> assign(:flyout_prompts, prompts)}
  end
end
