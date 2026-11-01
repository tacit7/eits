defmodule EyeInTheSkyWeb.Components.DmPage.ToolsTab do
  @moduledoc """
  Renders the Tools tab on the DM page.

  Shows what a Claude session reported at init: model, permission mode, tools list,
  MCP servers, plugins, agents, and skills. Data comes from the system/init event
  stored in session.settings["cli_init"] by AgentWorker.
  """

  use EyeInTheSkyWeb, :html

  attr :session_init_data, :map, default: nil
  attr :provider, :string, required: true

  def tools_tab(assigns) do
    data = if is_map(assigns.session_init_data), do: assigns.session_init_data, else: %{}

    assigns =
      assigns
      |> assign(:tools, list_value(data, "tools"))
      |> assign(:mcp_servers, list_value(data, "mcp_servers"))
      |> assign(:plugins, list_value(data, "plugins"))
      |> assign(:skills, list_value(data, "skills"))
      |> assign(:agents, list_value(data, "agents"))
      |> assign(:has_init_snapshot, map_size(data) > 0)

    ~H"""
    <div id="dm-tools-tab" class="px-6 py-5 space-y-6 max-w-2xl">
      <%= if @provider == "claude" && @has_init_snapshot do %>
        <p id="tools-snapshot-label" class="text-mini text-base-content/50">
          Reported at session start
        </p>
        <%!-- Model + runtime info --%>
        <.init_section title="Runtime" icon="hero-cpu-chip">
          <.kv_row label="Model" value={@session_init_data["model"]} />
          <.kv_row label="Permission mode" value={@session_init_data["permission_mode"]} />
          <.kv_row label="Fast mode" value={@session_init_data["fast_mode_state"]} />
          <.kv_row label="Claude version" value={@session_init_data["claude_code_version"]} />
        </.init_section>

        <%!-- Tools --%>
        <.init_section
          :if={@tools != []}
          title={"Tools (#{length(@tools)})"}
          icon="hero-wrench-screwdriver"
        >
          <div class="flex flex-wrap gap-1.5 pt-1">
            <span
              :for={tool <- @tools}
              class="inline-flex items-center px-2 py-0.5 rounded bg-base-content/[0.06] text-base-content/60 font-mono text-mini"
            >
              {item_name(tool)}
            </span>
          </div>
        </.init_section>

        <%!-- MCP servers --%>
        <.init_section
          :if={@mcp_servers != []}
          title={"MCP Servers (#{length(@mcp_servers)})"}
          icon="hero-server"
        >
          <div class="space-y-1 pt-1">
            <%= for srv <- @mcp_servers do %>
              <div class="flex items-center gap-2">
                <span class={[
                  "size-1.5 rounded-full flex-shrink-0",
                  item_status(srv) == "connected" && "bg-success",
                  item_status(srv) not in [nil, "connected"] && "bg-error",
                  is_nil(item_status(srv)) && "bg-base-content/30"
                ]}>
                </span>
                <span class="font-mono text-mini text-base-content/70">{item_name(srv)}</span>
                <%= if item_status(srv) && item_status(srv) != "connected" do %>
                  <span class="text-micro text-error/70 font-mono">{item_status(srv)}</span>
                <% end %>
              </div>
            <% end %>
          </div>
        </.init_section>

        <%!-- Plugins --%>
        <.init_section
          :if={@plugins != []}
          title={"Plugins (#{length(@plugins)})"}
          icon="hero-puzzle-piece"
        >
          <div class="space-y-1.5 pt-1">
            <%= for plugin <- @plugins do %>
              <div class="space-y-0.5">
                <div class="font-mono text-mini text-base-content/70 font-semibold">
                  {item_name(plugin)}
                </div>
                <%= if is_map(plugin) && plugin["path"] do %>
                  <div class="font-mono text-micro text-base-content/40 truncate">
                    {plugin["path"]}
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </.init_section>

        <%!-- Skills --%>
        <.init_section
          :if={@skills != []}
          title={"Skills (#{length(@skills)})"}
          icon="hero-academic-cap"
        >
          <div class="flex flex-wrap gap-1.5 pt-1">
            <span
              :for={skill <- @skills}
              class="inline-flex items-center px-2 py-0.5 rounded bg-base-content/[0.06] text-base-content/60 font-mono text-mini"
            >
              {item_name(skill)}
            </span>
          </div>
        </.init_section>

        <%!-- Agents --%>
        <.init_section
          :if={@agents != []}
          title={"Sub-agents (#{length(@agents)})"}
          icon="hero-user-group"
        >
          <div class="flex flex-wrap gap-1.5 pt-1">
            <span
              :for={agent <- @agents}
              class="inline-flex items-center px-2 py-0.5 rounded bg-base-content/[0.06] text-base-content/60 font-mono text-mini"
            >
              {item_name(agent)}
            </span>
          </div>
        </.init_section>
      <% else %>
        <div class="flex flex-col items-center justify-center py-16 text-center gap-3">
          <.icon name="hero-wrench-screwdriver" class="size-8 text-base-content/20" />
          <p :if={@provider == "claude"} class="text-message text-base-content/40">
            No Claude init snapshot has been reported for this session.
          </p>
          <p :if={@provider == "codex"} class="text-message text-base-content/40">
            Codex tool inventory has not been reported for this session.
          </p>
          <p :if={@provider not in ["claude", "codex"]} class="text-message text-base-content/40">
            Tool inventory has not been reported for this provider.
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  defp list_value(data, key) do
    case data[key] do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp item_name(%{"name" => name}) when is_binary(name), do: name
  defp item_name(value) when is_binary(value), do: value
  defp item_name(value), do: inspect(value)

  defp item_status(%{"status" => status}) when is_binary(status), do: status
  defp item_status(_), do: nil

  # ---------------------------------------------------------------------------
  # Private components
  # ---------------------------------------------------------------------------

  attr :title, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp init_section(assigns) do
    ~H"""
    <div>
      <div class="flex items-center gap-1.5 mb-2">
        <.icon name={@icon} class="size-3.5 text-base-content/40" />
        <h3 class="text-mini font-semibold text-base-content/50 uppercase tracking-normal">
          {@title}
        </h3>
      </div>
      <div class="rounded-box bg-base-content/[0.03] border border-base-content/[0.06] px-3 py-2.5">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, default: nil

  defp kv_row(assigns) do
    ~H"""
    <%= if @value do %>
      <div class="flex items-center gap-3 py-0.5">
        <span class="text-mini text-base-content/40 w-28 flex-shrink-0">{@label}</span>
        <span class="text-mini font-mono text-base-content/70">{@value}</span>
      </div>
    <% end %>
    """
  end
end
