defmodule EyeInTheSkyWebWeb.OverviewLive.Usage do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.{Sessions, Commits, Repo}
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    stats = load_stats()

    socket =
      socket
      |> assign(:page_title, "Usage")
      |> assign(:stats, stats)

    {:ok, socket}
  end

  defp load_stats do
    total_sessions =
      from(s in Sessions.Session, select: count(s.id))
      |> Repo.one()

    active_sessions =
      from(s in Sessions.Session, where: is_nil(s.ended_at), select: count(s.id))
      |> Repo.one()

    total_commits =
      from(c in Commits.Commit, select: count(c.id))
      |> Repo.one()

    total_notes =
      from(n in EyeInTheSkyWeb.Notes.Note, select: count(n.id))
      |> Repo.one()

    total_tasks =
      from(t in EyeInTheSkyWeb.Tasks.Task, select: count(t.id))
      |> Repo.one()

    total_messages =
      from(m in EyeInTheSkyWeb.Messages.Message, select: count(m.id))
      |> Repo.one()

    %{
      total_sessions: total_sessions,
      active_sessions: active_sessions,
      total_commits: total_commits,
      total_notes: total_notes,
      total_tasks: total_tasks,
      total_messages: total_messages
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component module={EyeInTheSkyWebWeb.Components.Navbar} id="navbar" />
    <EyeInTheSkyWebWeb.Components.OverviewNav.render current_tab={:usage} />

    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-6xl mx-auto">
        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
          <.stat_card label="Total Sessions" value={@stats.total_sessions} />
          <.stat_card label="Active Sessions" value={@stats.active_sessions} color="success" />
          <.stat_card label="Commits" value={@stats.total_commits} />
          <.stat_card label="Notes" value={@stats.total_notes} />
          <.stat_card label="Tasks" value={@stats.total_tasks} />
          <.stat_card label="Messages" value={@stats.total_messages} />
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :color, :string, default: nil

  defp stat_card(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm">
      <div class="card-body p-4 text-center">
        <p class="text-xs text-base-content/60 uppercase tracking-wider">{@label}</p>
        <p class={"text-3xl font-bold #{if @color == "success", do: "text-success", else: "text-base-content"}"}>
          {@value}
        </p>
      </div>
    </div>
    """
  end
end
