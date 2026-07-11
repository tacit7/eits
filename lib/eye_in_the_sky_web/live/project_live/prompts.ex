defmodule EyeInTheSkyWeb.ProjectLive.Prompts do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Editors
  alias EyeInTheSky.Events
  alias EyeInTheSky.Prompts
  alias EyeInTheSky.Settings
  alias EyeInTheSkyWeb.Helpers.ViewHelpers
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers
  import EyeInTheSkyWeb.Components.OpenInEditorButton
  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  import EyeInTheSkyWeb.Live.Shared.PromptsHelpers, only: [handle_duplicate_prompt: 3, handle_deactivate_prompt: 4]

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    socket =
      socket
      |> mount_project(params, sidebar_tab: :prompts, page_title_prefix: "Prompts")
      |> assign(:search_query, "")
      |> assign(:show_all, false)
      |> assign(:prompts, [])
      |> assign(:selected_prompt, nil)
      |> assign(:detail_tab, :preview)
      |> assign(:installed_editors, Editors.detect_installed())
      |> assign(:preferred_editor, Settings.get("preferred_editor") || "code")

    if connected?(socket), do: Events.broadcast_rail_context(socket)
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"show_all" => "true"} = _params, _uri, socket) do
    socket =
      socket
      |> assign(:show_all, true)
      |> then(fn s -> if connected?(s), do: load_prompts(s), else: s end)

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    socket =
      socket
      |> assign(:show_all, false)
      |> then(fn s -> if connected?(s), do: load_prompts(s), else: s end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    effective_query = if String.length(String.trim(query)) >= 4, do: query, else: ""

    socket =
      socket
      |> assign(:search_query, effective_query)
      |> load_prompts()

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_prompt", %{"uuid" => uuid}, socket) do
    selected = Enum.find(socket.assigns.prompts, &(&1.uuid == uuid))

    if selected && Phoenix.LiveView.connected?(socket) do
      Events.subscribe_prompt(selected.id)
      Events.subscribe_editor_sync(:prompt, selected.id)
    end

    {:noreply, assign(socket, selected_prompt: selected, detail_tab: :preview)}
  end

  @impl true
  def handle_event("duplicate_prompt", %{"uuid" => uuid}, socket) do
    handle_duplicate_prompt(uuid, socket, &load_prompts/1)
  end

  @impl true
  def handle_event("deactivate_prompt", %{"uuid" => uuid}, socket) do
    handle_deactivate_prompt(uuid, socket, &load_prompts/1, &maybe_clear_selected_prompt/2)
  end

  @impl true
  def handle_event("set_detail_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :detail_tab, String.to_existing_atom(tab))}
  end

  @impl true
  def handle_event("edit_content", _, socket),
    do: {:noreply, assign(socket, :detail_tab, :edit)}

  @impl true
  def handle_event("cancel_edit", _, socket),
    do: {:noreply, assign(socket, :detail_tab, :preview)}

  @impl true
  def handle_event("file_changed", %{"content" => content}, socket) do
    case socket.assigns.selected_prompt do
      nil ->
        {:noreply, socket}

      prompt ->
        case Prompts.update_prompt(prompt, %{prompt_text: content}) do
          {:ok, updated} ->
            socket =
              socket
              |> load_prompts()
              |> assign(:selected_prompt, updated)
              |> assign(:detail_tab, :preview)
              |> put_flash(:info, "Prompt saved")

            {:noreply, socket}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to save prompt")}
        end
    end
  end

  @impl true
  def handle_event("open_in_editor", %{"editor" => editor_id, "id" => id_str}, socket) do
    case Integer.parse(id_str) do
      {id, ""} -> ViewHelpers.handle_open_in_editor_record(:prompt, id, editor_id, socket)
      _ -> {:noreply, put_flash(socket, :error, "Invalid prompt ID")}
    end
  end

  def handle_event("open_in_editor", _params, socket) do
    {:noreply, put_flash(socket, :error, "No record selected")}
  end

  @impl true
  def handle_info({:prompt_updated, prompt}, socket) do
    if socket.assigns.selected_prompt && socket.assigns.selected_prompt.id == prompt.id do
      {:noreply, assign(socket, :selected_prompt, prompt)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:editor_sync_failed, :prompt, id, _reason}, socket) do
    if socket.assigns.selected_prompt && socket.assigns.selected_prompt.id == id do
      {:noreply, put_flash(socket, :error, "Editor sync failed — check your editor")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp maybe_clear_selected_prompt(socket, uuid) do
    if socket.assigns.selected_prompt && socket.assigns.selected_prompt.uuid == uuid do
      assign(socket, :selected_prompt, nil)
    else
      socket
    end
  end

  defp load_prompts(socket) do
    show_all = Map.get(socket.assigns, :show_all, false)
    query = socket.assigns.search_query

    prompts =
      if show_all do
        if String.trim(query) != "" do
          Prompts.search_prompts(query)
        else
          Prompts.list_prompts()
        end
      else
        project_id = socket.assigns.project_id

        if String.trim(query) != "" do
          Prompts.search_prompts(query, project_id)
        else
          Prompts.list_prompts(project_id: project_id)
        end
      end

    assign(socket, :prompts, prompts)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["flex overflow-hidden", @selected_prompt && "flex-1"]}>
      <%!-- List panel --%>
      <div
        class={[
          "overflow-y-auto px-4 sm:px-6 py-6",
          if(@selected_prompt,
            do: "w-[440px] flex-shrink-0 border-r border-base-content/8",
            else: "w-full max-w-3xl mx-auto"
          )
        ]}
        style="scrollbar-width: none;"
      >
        <%= if @prompts != [] do %>
          <div class="divide-y divide-base-content/5" data-vim-list>
            <%= for prompt <- @prompts do %>
              <% selected? = @selected_prompt && @selected_prompt.uuid == prompt.uuid %>
              <div class="py-0.5">
                <div
                  class={[
                    "py-2.5 px-3 flex flex-col gap-0.5 cursor-pointer rounded-lg transition-colors",
                    "[&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50",
                    if(selected?,
                      do: "bg-primary/5",
                      else: "hover:bg-base-200/40"
                    )
                  ]}
                  phx-click="select_prompt"
                  phx-value-uuid={prompt.uuid}
                  data-vim-list-item
                  role="button"
                  data-ctx="prompt"
                  data-ctx-id={prompt.id}
                  data-ctx-uuid={prompt.uuid}
                  data-ctx-slug={prompt.slug}
                  data-ctx-path={~p"/projects/#{@project.id}/prompts/#{prompt.uuid}"}
                >
                  <div class="flex items-center gap-2">
                    <.icon
                      name="hero-chat-bubble-left-right"
                      class={"size-3.5 flex-shrink-0 " <> if(selected?, do: "text-primary", else: "text-base-content/35")}
                    />
                    <span class={"text-sm font-semibold " <> if(selected?, do: "text-primary", else: "text-base-content/85")}>
                      {prompt.name}
                    </span>
                    <code class="text-[10px] font-mono text-base-content/40 bg-base-content/5 px-1.5 py-0.5 rounded">
                      {prompt.slug}
                    </code>
                    <%= if !prompt.active do %>
                      <span class="badge badge-xs badge-ghost">Inactive</span>
                    <% end %>
                  </div>
                  <%= if prompt.description do %>
                    <p class="text-xs text-base-content/55 leading-snug pl-5 line-clamp-2">
                      {prompt.description}
                    </p>
                  <% end %>
                  <div class="flex items-center gap-1.5 pl-5 mt-0.5">
                    <span class={[
                      "inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium",
                      if(is_nil(prompt.project_id),
                        do: "bg-primary/10 text-primary/70",
                        else: "bg-secondary/10 text-secondary/70"
                      )
                    ]}>
                      {if is_nil(prompt.project_id), do: "global", else: "project"}
                    </span>
                    <span class="text-base-content/20 text-xs">&middot;</span>
                    <span class="text-[10px] text-base-content/40 tabular-nums">
                      v{prompt.version}
                    </span>
                    <%= if prompt.tags do %>
                      <span class="text-base-content/20 text-xs">&middot;</span>
                      <span class="text-[10px] text-base-content/35 truncate">
                        {prompt.tags}
                      </span>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <.empty_state
            id="project-prompts-empty"
            icon="hero-chat-bubble-left-right"
            title={if @search_query != "", do: "No prompts found", else: "No prompts yet"}
            subtitle={
              if @search_query != "",
                do: "Try adjusting your search",
                else: "Create project-specific prompts to use with your agents"
            }
          />
        <% end %>
      </div>

      <%!-- Detail panel --%>
      <%= if @selected_prompt do %>
        <div class="hidden md:flex flex-col flex-1 overflow-hidden">
          <%= if @detail_tab == :edit do %>
            <div class="flex-shrink-0 px-4 py-2 border-b border-base-content/8 flex items-center gap-3">
              <span class="text-xs text-base-content/50 font-mono truncate flex-1">{@selected_prompt.slug}</span>
              <span class="text-[10px] text-base-content/40">Ctrl+S to save</span>
              <button phx-click="cancel_edit" class="btn btn-ghost btn-xs">Cancel</button>
            </div>
          <% else %>
            <div class="flex-shrink-0 px-6 pt-5 pb-4 border-b border-base-content/8">
              <div class="flex items-start justify-between gap-4">
                <div class="min-w-0">
                  <div class="flex items-center gap-2 mb-1 flex-wrap">
                    <span class="text-base font-semibold text-base-content">
                      {@selected_prompt.name}
                    </span>
                    <span class={[
                      "inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium",
                      if(is_nil(@selected_prompt.project_id),
                        do: "bg-primary/10 text-primary/70",
                        else: "bg-secondary/10 text-secondary/70"
                      )
                    ]}>
                      {if is_nil(@selected_prompt.project_id), do: "global", else: "project"}
                    </span>
                    <span class="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-base-content/5 text-base-content/50">
                      v{@selected_prompt.version}
                    </span>
                    <%= if !@selected_prompt.active do %>
                      <span class="badge badge-xs badge-ghost">Inactive</span>
                    <% end %>
                  </div>
                  <p class="text-xs text-base-content/45 font-mono">{@selected_prompt.slug}</p>
                  <%= if @selected_prompt.description do %>
                    <p class="text-sm text-base-content/60 mt-1.5 leading-snug">
                      {@selected_prompt.description}
                    </p>
                  <% end %>
                  <%= if @selected_prompt.tags do %>
                    <div class="flex flex-wrap gap-1 mt-2">
                      <%= for tag <- String.split(@selected_prompt.tags, ",", trim: true) do %>
                        <span class="badge badge-xs">
                          {String.trim(tag)}
                        </span>
                      <% end %>
                    </div>
                  <% end %>
                </div>
                <div class="flex items-center gap-1 flex-shrink-0">
                  <.open_in_editor_button
                    record_id={@selected_prompt.id}
                    installed_editors={@installed_editors}
                    preferred_editor={@preferred_editor}
                  />
                  <.link
                    navigate={~p"/projects/#{@project.id}/prompts/#{@selected_prompt.uuid}"}
                    class="btn btn-ghost btn-xs gap-1"
                  >
                    <.icon name="hero-arrow-top-right-on-square" class="size-3.5" /> Full edit
                  </.link>
                </div>
              </div>
              <div class="flex items-center gap-1 mt-3">
                <button
                  phx-click="set_detail_tab"
                  phx-value-tab="preview"
                  class={"px-3 py-1 rounded text-xs font-medium " <>
                    if(@detail_tab == :preview,
                      do: "bg-base-content/8 text-base-content",
                      else: "text-base-content/50 hover:text-base-content")}
                >
                  Preview
                </button>
                <button
                  phx-click="set_detail_tab"
                  phx-value-tab="raw"
                  class={"px-3 py-1 rounded text-xs font-medium " <>
                    if(@detail_tab == :raw,
                      do: "bg-base-content/8 text-base-content",
                      else: "text-base-content/50 hover:text-base-content")}
                >
                  Raw
                </button>
                <button
                  phx-click="edit_content"
                  class="px-3 py-1 rounded text-xs font-medium text-base-content/50 hover:text-base-content"
                >
                  Edit
                </button>
              </div>
            </div>
          <% end %>

          <%= if @detail_tab == :edit do %>
            <div
              id={"proj-prompt-editor-#{@selected_prompt.uuid}"}
              phx-hook="CodeMirror"
              phx-update="ignore"
              data-content={Base.encode64(@selected_prompt.prompt_text || "")}
              data-lang="markdown"
              class="flex-1 overflow-hidden min-h-0"
            ></div>
          <% else %>
            <div class="flex-1 overflow-y-auto" style="scrollbar-width: none;">
              <%= if @detail_tab == :preview do %>
                <div
                  id={"proj-prompt-viewer-#{@selected_prompt.uuid}"}
                  class="dm-markdown px-6 py-4 text-sm text-base-content leading-relaxed"
                  phx-hook="MarkdownMessage"
                  data-raw-body={@selected_prompt.prompt_text}
                >
                </div>
              <% else %>
                <pre class="px-6 py-4 text-xs font-mono text-base-content/75 whitespace-pre-wrap break-words leading-relaxed">{@selected_prompt.prompt_text}</pre>
              <% end %>
              <%= if @selected_prompt.created_by do %>
                <div class="px-6 pb-4 text-xs text-base-content/40">
                  Created by <span class="text-base-content/60">{@selected_prompt.created_by}</span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
