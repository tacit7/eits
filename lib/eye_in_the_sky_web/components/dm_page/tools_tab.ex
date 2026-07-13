defmodule EyeInTheSkyWeb.Components.DmPage.ToolsTab do
  @moduledoc """
  Renders the Tools tab on the DM page.

  Shows what the Claude session had at init: model, permission mode, tools list,
  MCP servers, plugins, agents, and skills. Data comes from the system/init event
  stored in session.settings["cli_init"] by AgentWorker.
  """

  use EyeInTheSkyWeb, :html

  attr :session_init_data, :map, default: nil

  def tools_tab(assigns) do
    ~H"""
    <div class="px-6 py-5 space-y-6 max-w-2xl">
      <%= if @session_init_data do %>
        <%!-- Model + runtime info --%>
        <.init_section title="Runtime" icon="hero-cpu-chip">
          <.kv_row label="Model" value={@session_init_data["model"]} />
          <.kv_row label="Permission mode" value={@session_init_data["permission_mode"]} />
          <.kv_row label="Fast mode" value={@session_init_data["fast_mode_state"]} />
          <.kv_row label="Claude version" value={@session_init_data["claude_code_version"]} />
        </.init_section>

        <%!-- Tools --%>
        <.init_section
          :if={@session_init_data["tools"] != []}
          title={"Tools (#{length(@session_init_data["tools"])})"}
          icon="hero-wrench-screwdriver"
        >
          <div class="flex flex-wrap gap-1.5 pt-1">
            <span
              :for={tool <- @session_init_data["tools"]}
              class="inline-flex items-center px-2 py-0.5 rounded bg-base-content/[0.06] text-base-content/60 font-mono text-mini"
            >
              {tool}
            </span>
          </div>
        </.init_section>

        <%!-- MCP servers --%>
        <.init_section
          :if={@session_init_data["mcp_servers"] not in [[], nil]}
          title={"MCP Servers (#{length(@session_init_data["mcp_servers"] || [])})"}
          icon="hero-server"
        >
          <div class="space-y-1 pt-1">
            <%= for srv <- (@session_init_data["mcp_servers"] || []) do %>
              <div class="flex items-center gap-2">
                <span class={[
                  "size-1.5 rounded-full flex-shrink-0",
                  srv["status"] == "connected" && "bg-success",
                  srv["status"] != "connected" && "bg-error"
                ]}>
                </span>
                <span class="font-mono text-mini text-base-content/70">{srv["name"] || srv}</span>
                <%= if srv["status"] && srv["status"] != "connected" do %>
                  <span class="text-micro text-error/70 font-mono">{srv["status"]}</span>
                <% end %>
              </div>
            <% end %>
          </div>
        </.init_section>

        <%!-- Plugins --%>
        <.init_section
          :if={@session_init_data["plugins"] not in [[], nil]}
          title={"Plugins (#{length(@session_init_data["plugins"] || [])})"}
          icon="hero-puzzle-piece"
        >
          <div class="space-y-1.5 pt-1">
            <%= for plugin <- (@session_init_data["plugins"] || []) do %>
              <div class="space-y-0.5">
                <div class="font-mono text-mini text-base-content/70 font-semibold">
                  {plugin["name"] || plugin}
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
          :if={@session_init_data["skills"] not in [[], nil]}
          title={"Skills (#{length(@session_init_data["skills"] || [])})"}
          icon="hero-academic-cap"
        >
          <div class="flex flex-wrap gap-1.5 pt-1">
            <span
              :for={skill <- (@session_init_data["skills"] || [])}
              class="inline-flex items-center px-2 py-0.5 rounded bg-base-content/[0.06] text-base-content/60 font-mono text-mini"
            >
              {if is_map(skill), do: skill["name"] || inspect(skill), else: skill}
            </span>
          </div>
        </.init_section>

        <%!-- Agents --%>
        <.init_section
          :if={@session_init_data["agents"] not in [[], nil]}
          title={"Sub-agents (#{length(@session_init_data["agents"] || [])})"}
          icon="hero-user-group"
        >
          <div class="flex flex-wrap gap-1.5 pt-1">
            <span
              :for={agent <- (@session_init_data["agents"] || [])}
              class="inline-flex items-center px-2 py-0.5 rounded bg-base-content/[0.06] text-base-content/60 font-mono text-mini"
            >
              {if is_map(agent), do: agent["name"] || inspect(agent), else: agent}
            </span>
          </div>
        </.init_section>
      <% else %>
        <div class="flex flex-col items-center justify-center py-16 text-center gap-3">
          <.icon name="hero-wrench-screwdriver" class="size-8 text-base-content/20" />
          <p class="text-sm text-base-content/40">
            No init data yet. Start a session to see what tools are available.
          </p>
        </div>
      <% end %>
    </div>
    """
  end

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
        <h3 class="text-xs font-semibold text-base-content/50 uppercase tracking-wide">
          {@title}
        </h3>
      </div>
      <div class="rounded-lg bg-base-content/[0.03] border border-base-content/[0.06] px-3 py-2.5">
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
