defmodule EyeInTheSkyWeb.ProjectLive.Skills do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Editors
  alias EyeInTheSky.Events
  alias EyeInTheSky.Settings
  alias EyeInTheSkyWeb.Helpers.FileHelpers
  alias EyeInTheSkyWeb.Helpers.ViewHelpers
  alias EyeInTheSkyWeb.Live.Shared.DefinitionFileActions
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers
  import EyeInTheSkyWeb.Components.OpenInEditorButton
  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  import EyeInTheSkyWeb.Live.Shared.SkillsHelpers

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    socket =
      socket
      |> mount_project(params,
        sidebar_tab: :skills,
        page_title_prefix: "Skills"
      )
      |> assign(:search_query, "")
      |> assign(:sort_by, "name_asc")
      |> assign(:type_filter, "all")
      |> assign(:scope_filter, "all")
      |> assign(:skills, [])
      |> assign(:filtered_skills, [])
      |> assign(:selected_skill, nil)
      |> assign(:detail_tab, :preview)
      |> assign(:installed_editors, Editors.detect_installed())
      |> assign(:preferred_editor, Settings.get("preferred_editor") || "code")

    socket = if connected?(socket), do: load_skills(socket), else: socket

    if connected?(socket), do: Events.broadcast_rail_context(socket)
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"skill" => skill_id}, _uri, socket) do
    selected = Enum.find(socket.assigns.skills, &(&1.id == skill_id))
    {:noreply, socket |> assign(:selected_skill, selected) |> assign(:detail_tab, :preview)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("search", params, socket),
    do: handle_search(params, socket, &load_skills/1)

  @impl true
  def handle_event("sort_skills", params, socket),
    do: handle_sort_skills(params, socket, &load_skills/1)

  @impl true
  def handle_event("filter_type", params, socket),
    do: handle_filter_type(params, socket, &load_skills/1)

  @impl true
  def handle_event("filter_scope", params, socket),
    do: handle_filter_scope(params, socket, &load_skills/1)

  @impl true
  def handle_event("select_skill", %{"id" => id}, socket) do
    selected =
      if socket.assigns.selected_skill && socket.assigns.selected_skill.id == id do
        nil
      else
        Enum.find(socket.assigns.skills, &(&1.id == id))
      end

    {:noreply, socket |> assign(:selected_skill, selected) |> assign(:detail_tab, :preview)}
  end

  @impl true
  def handle_event("close_viewer", _params, socket) do
    {:noreply, assign(socket, :selected_skill, nil)}
  end

  @impl true
  def handle_event("set_detail_tab", params, socket),
    do: ViewHelpers.handle_set_detail_tab(params, socket)

  @impl true
  def handle_event("open_in_editor", %{"editor" => editor_id, "path" => path}, socket) do
    ViewHelpers.handle_open_in_editor_with_guard(path, editor_id, socket, &skill_write_allowed?/2)
  end

  @impl true
  def handle_event("duplicate_definition_file", %{"path" => path}, socket) do
    DefinitionFileActions.handle_duplicate(path, socket, &skill_write_allowed?/2, &load_skills/1)
  end

  @impl true
  def handle_event("delete_definition_file", %{"path" => path}, socket) do
    DefinitionFileActions.handle_delete(
      path,
      socket,
      &skill_write_allowed?/2,
      &load_skills/1,
      &maybe_clear_selected(&1, path)
    )
  end

  @impl true
  def handle_event("edit_content", _, socket),
    do: {:noreply, assign(socket, :detail_tab, :edit)}

  @impl true
  def handle_event("cancel_edit", _, socket),
    do: {:noreply, assign(socket, :detail_tab, :preview)}

  @impl true
  def handle_event("file_changed", %{"content" => content}, socket) do
    case socket.assigns.selected_skill do
      %{abs_path: path, id: id} when is_binary(path) ->
        if skill_write_allowed?(path, socket) do
          case File.write(path, content) do
            :ok ->
              socket =
                socket
                |> load_skills()
                |> reselect_skill(id)
                |> assign(:detail_tab, :preview)
                |> put_flash(:info, "Skill saved")

              {:noreply, socket}

            {:error, reason} ->
              {:noreply, put_flash(socket, :error, "Failed to save skill: #{inspect(reason)}")}
          end
        else
          {:noreply, put_flash(socket, :error, "Write not permitted for this path")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "No file path available")}
    end
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Mobile-only controls --%>
    <div class="md:hidden flex flex-wrap items-center gap-2 px-4 pt-3 pb-1">
      <form phx-change="sort_skills">
        <label for="proj-skills-sort-mobile" class="sr-only">Sort skills</label>
        <select
          id="proj-skills-sort-mobile"
          name="by"
          class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 min-h-[44px] text-mini"
        >
          <option value="name_asc" selected={@sort_by == "name_asc"}>Name A–Z</option>
          <option value="name_desc" selected={@sort_by == "name_desc"}>Name Z–A</option>
          <option value="recent" selected={@sort_by == "recent"}>Recent</option>
          <option value="size_desc" selected={@sort_by == "size_desc"}>Largest</option>
          <option value="size_asc" selected={@sort_by == "size_asc"}>Smallest</option>
        </select>
      </form>
      <form phx-change="filter_type">
        <label for="proj-skills-type-mobile" class="sr-only">Filter by type</label>
        <select
          id="proj-skills-type-mobile"
          name="filter"
          class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 min-h-[44px] text-mini"
        >
          <option value="all" selected={@type_filter == "all"}>All Types</option>
          <option value="skills" selected={@type_filter == "skills"}>Skills</option>
          <option value="commands" selected={@type_filter == "commands"}>Commands</option>
        </select>
      </form>
      <form phx-change="filter_scope">
        <label for="proj-skills-scope-mobile" class="sr-only">Filter by source</label>
        <select
          id="proj-skills-scope-mobile"
          name="scope"
          class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 min-h-[44px] text-mini"
        >
          <option value="all" selected={@scope_filter == "all"}>All Sources</option>
          <option value="global" selected={@scope_filter == "global"}>Global</option>
          <option value="project" selected={@scope_filter == "project"}>Project</option>
        </select>
      </form>
    </div>

    <div class={[
      "flex overflow-hidden",
      @selected_skill && "flex-1"
    ]}>
      <%!-- List panel --%>
      <div class={[
        "overflow-y-auto px-4 sm:px-6 py-6",
        if(@selected_skill,
          do: "w-[440px] flex-shrink-0 border-r border-base-content/8",
          else: "w-full max-w-3xl mx-auto"
        )
      ]}>
        <%= if @filtered_skills != [] do %>
          <div class="divide-y divide-base-content/5">
            <%= for skill <- @filtered_skills do %>
              <% selected? = @selected_skill && @selected_skill.id == skill.id %>
              <div class={["py-0.5", selected? && "relative"]}>
                <div class="eits-disclosure overflow-visible">
                  <input
                    type="checkbox"
                    class="min-h-0 p-0"
                    phx-click="select_skill"
                    phx-value-id={skill.id}
                  />
                  <div
                    class={[
                      "eits-disclosure__summary py-2.5 px-3 min-h-0 flex flex-col gap-0.5 cursor-pointer rounded-box",
                      if(selected?,
                        do: "bg-primary/5",
                        else: "hover:bg-base-content/4"
                      )
                    ]}
                    data-ctx="definition_file"
                    data-ctx-abs-path={skill.abs_path}
                    data-ctx-content={skill.content}
                    data-ctx-editor={@preferred_editor}
                    data-ctx-is-dir={to_string(skill.source in [:skills, :project_skills])}
                  >
                    <div class="flex items-center gap-2">
                      <.icon
                        name="hero-puzzle-piece"
                        class={"size-3.5 flex-shrink-0 " <>
                          if(selected?, do: "text-primary", else: "text-base-content/35")}
                      />
                      <code class={"text-message font-semibold " <>
                        if(selected?, do: "text-primary", else: "text-base-content/85")}>
                        /{skill.slug}
                      </code>
                    </div>
                    <p class="text-mini text-base-content/55 leading-snug pl-5 line-clamp-2">
                      {skill.description}
                    </p>
                    <div class="flex items-center gap-1.5 pl-5 mt-0.5">
                      <span class={"eits-chip " <>
                        source_badge_class(skill.source)}>
                        {source_label(skill.source)}
                      </span>
                      <span class="text-base-content/20 text-mini">|</span>
                      <span class="text-micro text-base-content/40 tabular-nums">
                        {FileHelpers.format_size(skill.size)}
                      </span>
                      <span class="text-base-content/20 text-mini">|</span>
                      <span class="text-micro text-base-content/35 font-mono truncate">
                        {skill.path}
                      </span>
                    </div>
                  </div>
                  <div class="eits-disclosure__content md:hidden px-3 pb-3">
                    <div
                      id={"proj-skill-mobile-#{skill.id}"}
                      class="dm-markdown text-message text-base-content leading-relaxed mt-2"
                      phx-hook="MarkdownMessage"
                      data-raw-body={skill.content}
                    >
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <.empty_state
            id="proj-skills-empty"
            icon="hero-code-bracket"
            title={
              if @search_query != "" || @type_filter != "all" || @scope_filter != "all",
                do: "No skills found",
                else: "No skills yet"
            }
            subtitle={
              if @search_query != "" || @type_filter != "all" || @scope_filter != "all",
                do: "Try adjusting your search or filters",
                else: "Add .md files to .claude/commands/ or .claude/skills/ in your project"
            }
          />
        <% end %>
      </div>

      <%!-- Desktop detail panel --%>
      <%= if @selected_skill do %>
        <div class="hidden md:flex flex-col flex-1 overflow-hidden">
          <%= if @detail_tab == :edit do %>
            <div class="flex-shrink-0 px-4 py-2 border-b border-base-content/8 flex items-center gap-3">
              <code class="text-mini text-base-content/50 font-mono truncate flex-1">
                {@selected_skill.path}
              </code>
              <span class="text-micro text-base-content/40">Ctrl+S to save</span>
              <button phx-click="cancel_edit" class="eits-action eits-action--ghost h-7 min-h-0 px-2">
                Cancel
              </button>
            </div>
          <% else %>
            <div class="flex-shrink-0 px-6 pt-5 pb-4 border-b border-base-content/8">
              <div class="flex items-start justify-between gap-4">
                <div class="min-w-0">
                  <div class="flex items-center gap-2 mb-1">
                    <code class="text-message font-semibold text-base-content">
                      /{@selected_skill.slug}
                    </code>
                    <span class={"eits-chip " <>
                      source_badge_class(@selected_skill.source)}>
                      {source_label(@selected_skill.source)}
                    </span>
                  </div>
                  <p class="text-mini text-base-content/45 font-mono truncate">
                    {@selected_skill.path}
                  </p>
                  <p class="text-message text-base-content/60 mt-1.5 leading-snug">
                    {@selected_skill.description}
                  </p>
                </div>
                <div class="flex items-center gap-1 flex-shrink-0">
                  <.open_in_editor_button
                    path={@selected_skill.abs_path || ""}
                    installed_editors={@installed_editors}
                    preferred_editor={@preferred_editor}
                  />
                  <button
                    phx-click="close_viewer"
                    class="eits-action eits-action--ghost eits-action--icon h-9 min-h-0 min-w-9 flex-shrink-0"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
              </div>
              <div class="flex items-center gap-1 mt-3">
                <button
                  phx-click="set_detail_tab"
                  phx-value-tab="preview"
                  class={"eits-action h-7 min-h-0 px-3 " <>
                    if(@detail_tab == :preview,
                      do: "eits-action--primary",
                      else: "eits-action--ghost")}
                >
                  Preview
                </button>
                <button
                  phx-click="set_detail_tab"
                  phx-value-tab="raw"
                  class={"eits-action h-7 min-h-0 px-3 " <>
                    if(@detail_tab == :raw,
                      do: "eits-action--primary",
                      else: "eits-action--ghost")}
                >
                  Raw
                </button>
                <%= if is_binary(@selected_skill.abs_path) do %>
                  <button
                    phx-click="edit_content"
                    class="eits-action eits-action--ghost h-7 min-h-0 px-3"
                  >
                    Edit
                  </button>
                <% end %>
                <span class="ml-auto text-micro text-base-content/35 tabular-nums">
                  {FileHelpers.format_size(@selected_skill.size)}
                </span>
              </div>
            </div>
          <% end %>
          <%= if @detail_tab == :edit do %>
            <div
              id={"proj-skill-editor-#{@selected_skill.id}"}
              phx-hook="CodeMirror"
              phx-update="ignore"
              data-content={Base.encode64(@selected_skill.content || "")}
              data-lang={edit_language(@selected_skill)}
              class="flex-1 overflow-hidden min-h-0"
            >
            </div>
          <% else %>
            <div class="flex-1 overflow-y-auto">
              <%= if @detail_tab == :preview do %>
                <div
                  id={"proj-skill-viewer-#{@selected_skill.id}"}
                  class="dm-markdown px-6 py-4 text-message text-base-content leading-relaxed"
                  phx-hook="MarkdownMessage"
                  data-raw-body={@selected_skill.content}
                >
                </div>
              <% else %>
                <pre class="px-6 py-4 text-mini font-mono text-base-content/75 whitespace-pre-wrap break-words leading-relaxed">{@selected_skill.content}</pre>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp edit_language(%{path: path}) when is_binary(path), do: lang_from_path(path)
  defp edit_language(%{abs_path: path}) when is_binary(path), do: lang_from_path(path)
  defp edit_language(_), do: "markdown"

  defp lang_from_path(path) do
    case Path.extname(path) do
      ".yaml" -> "yaml"
      ".yml" -> "yaml"
      ".json" -> "json"
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".js" -> "javascript"
      ".ts" -> "typescript"
      ".css" -> "css"
      ".html" -> "html"
      ".heex" -> "html"
      ".sh" -> "shell"
      ".bash" -> "shell"
      ".md" -> "markdown"
      _ -> "markdown"
    end
  end

  defp reselect_skill(socket, id) do
    selected = Enum.find(socket.assigns.skills, &(&1.id == id))
    assign(socket, :selected_skill, selected)
  end

  defp skill_write_allowed?(path, socket) do
    expanded = Path.expand(path)
    expanded_user_skills = Path.expand("~/.claude/skills")
    expanded_user_commands = Path.expand("~/.claude/commands")

    project_roots =
      case socket.assigns[:project] do
        %{path: p} when is_binary(p) and p != "" ->
          [
            Path.expand(Path.join(p, ".claude/skills")),
            Path.expand(Path.join(p, ".claude/commands"))
          ]

        _ ->
          []
      end

    allowed = [expanded_user_skills, expanded_user_commands | project_roots]
    Enum.any?(allowed, fn root -> String.starts_with?(expanded, root <> "/") end)
  end

  defp maybe_clear_selected(socket, path) do
    if socket.assigns.selected_skill && socket.assigns.selected_skill.abs_path == path do
      assign(socket, :selected_skill, nil)
    else
      socket
    end
  end
end
