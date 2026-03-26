defmodule EyeInTheSkyWebWeb.OverviewLive.Approvals do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Assistants.ToolPolicy
  import EyeInTheSkyWebWeb.Helpers.ViewHelpers, only: [relative_time: 1]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "tool_approvals")
    end

    socket =
      socket
      |> assign(:page_title, "Approval Inbox")
      |> assign(:sidebar_tab, :approvals)
      |> assign(:sidebar_project, nil)
      |> assign(:filter, "pending")
      |> assign(:approvals, ToolPolicy.list_pending())

    {:ok, socket}
  end

  @impl true
  def handle_info({:approval_requested, _approval}, socket) do
    {:noreply, assign(socket, :approvals, load_approvals(socket.assigns.filter))}
  end

  @impl true
  def handle_info({:approval_updated, _approval}, socket) do
    {:noreply, assign(socket, :approvals, load_approvals(socket.assigns.filter))}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    reviewer_id = get_reviewer_id(socket)
    ToolPolicy.approve(String.to_integer(id), reviewer_id)
    {:noreply, assign(socket, :approvals, load_approvals(socket.assigns.filter))}
  end

  @impl true
  def handle_event("deny", %{"id" => id}, socket) do
    reviewer_id = get_reviewer_id(socket)
    ToolPolicy.deny(String.to_integer(id), reviewer_id)
    {:noreply, assign(socket, :approvals, load_approvals(socket.assigns.filter))}
  end

  @impl true
  def handle_event("set_filter", %{"filter" => filter}, socket) do
    socket =
      socket
      |> assign(:filter, filter)
      |> assign(:approvals, load_approvals(filter))

    {:noreply, socket}
  end

  @impl true
  def handle_event("expire_stale", _params, socket) do
    {:ok, count} = ToolPolicy.expire_stale()
    socket = put_flash(socket, :info, "Expired #{count} stale approval(s)")
    {:noreply, assign(socket, :approvals, load_approvals(socket.assigns.filter))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div class="flex items-center justify-between px-6 py-4 border-b border-white/10">
        <div>
          <h1 class="text-lg font-semibold text-white">Approval Inbox</h1>
          <p class="text-sm text-white/50">Review tool invocations requiring human sign-off</p>
        </div>
        <button
          phx-click="expire_stale"
          class="text-xs text-white/40 hover:text-white/70 transition-colors"
        >
          Expire stale
        </button>
      </div>

      <%!-- Filter tabs --%>
      <div class="flex gap-1 px-6 pt-4">
        <%= for {label, value} <- [{"Pending", "pending"}, {"Approved", "approved"}, {"Denied", "denied"}, {"All", "all"}] do %>
          <button
            phx-click="set_filter"
            phx-value-filter={value}
            class={[
              "px-3 py-1 rounded text-xs font-medium transition-colors",
              if(@filter == value,
                do: "bg-white/15 text-white",
                else: "text-white/40 hover:text-white/70"
              )
            ]}
          >
            {label}
          </button>
        <% end %>
      </div>

      <%!-- Approval list --%>
      <div class="flex-1 overflow-y-auto px-6 py-4 space-y-3">
        <%= if @approvals == [] do %>
          <div class="text-center py-12 text-white/30 text-sm">
            No <%= @filter %> approvals
          </div>
        <% else %>
          <%= for approval <- @approvals do %>
            <div class={[
              "rounded-lg border p-4 space-y-3",
              case approval.status do
                "pending"  -> "bg-amber-500/10 border-amber-500/30"
                "approved" -> "bg-emerald-500/10 border-emerald-500/20"
                "denied"   -> "bg-red-500/10 border-red-500/20"
                _          -> "bg-white/5 border-white/10"
              end
            ]}>
              <%!-- Header row --%>
              <div class="flex items-start justify-between gap-4">
                <div class="flex items-center gap-2 min-w-0">
                  <span class={[
                    "inline-flex items-center px-2 py-0.5 rounded text-xs font-mono font-semibold",
                    if(destructive_tool?(approval.tool_name),
                      do: "bg-red-500/20 text-red-300",
                      else: "bg-blue-500/20 text-blue-300"
                    )
                  ]}>
                    {approval.tool_name}
                  </span>
                  <%= if destructive_tool?(approval.tool_name) do %>
                    <span class="text-xs text-red-400 font-medium">destructive</span>
                  <% end %>
                </div>
                <span class="text-xs text-white/40 shrink-0">
                  {relative_time(approval.inserted_at)}
                </span>
              </div>

              <%!-- Session / assistant context --%>
              <div class="text-xs text-white/50 space-y-0.5">
                <%= if approval.session do %>
                  <div>Session: <span class="text-white/70 font-mono">{approval.session.uuid || approval.session_id}</span></div>
                <% end %>
                <%= if approval.assistant do %>
                  <div>Assistant: <span class="text-white/70">{approval.assistant.name}</span></div>
                <% end %>
                <%= if approval.expires_at do %>
                  <div>Expires: <span class="text-white/70">{relative_time(approval.expires_at)}</span></div>
                <% end %>
              </div>

              <%!-- Payload --%>
              <%= if approval.payload != %{} do %>
                <details class="text-xs">
                  <summary class="text-white/40 cursor-pointer hover:text-white/60 transition-colors">
                    View payload
                  </summary>
                  <pre class="mt-2 p-2 bg-black/30 rounded text-white/70 overflow-x-auto text-xs leading-relaxed"><%= Jason.encode!(approval.payload, pretty: true) %></pre>
                </details>
              <% end %>

              <%!-- Actions --%>
              <%= if approval.status == "pending" do %>
                <div class="flex gap-2 pt-1">
                  <button
                    phx-click="approve"
                    phx-value-id={approval.id}
                    class="px-3 py-1 rounded bg-emerald-500/20 hover:bg-emerald-500/30 text-emerald-300 text-xs font-medium transition-colors"
                  >
                    Approve
                  </button>
                  <button
                    phx-click="deny"
                    phx-value-id={approval.id}
                    class="px-3 py-1 rounded bg-red-500/20 hover:bg-red-500/30 text-red-300 text-xs font-medium transition-colors"
                  >
                    Deny
                  </button>
                </div>
              <% else %>
                <div class="text-xs text-white/40">
                  <%= case approval.status do %>
                    <% "approved" -> %> Approved <%= if approval.reviewed_at, do: relative_time(approval.reviewed_at) %>
                    <% "denied"   -> %> Denied <%= if approval.reviewed_at, do: relative_time(approval.reviewed_at) %>
                    <% "expired"  -> %> Expired
                    <% _          -> %> {approval.status}
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  defp load_approvals("pending"), do: ToolPolicy.list_pending()
  defp load_approvals("all"),     do: ToolPolicy.list_approvals()
  defp load_approvals(status),    do: ToolPolicy.list_approvals(status: status)

  defp get_reviewer_id(socket) do
    case socket.assigns[:current_user] do
      nil  -> nil
      user -> user.id
    end
  end

  @destructive_tools ~w(run_shell_command write_file)
  defp destructive_tool?(name), do: name in @destructive_tools
end
