defmodule EyeInTheSkyWeb.Components.Rail.Flyout.JobsSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :jobs, :list, default: []
  attr :sidebar_project, :any, default: nil

  def jobs_content(assigns) do
    ~H"""
    <div class="px-3 pt-2 pb-1 border-b border-base-content/8 flex items-center gap-3">
      <.link
        navigate="/jobs"
        class="text-xs text-base-content/50 hover:text-base-content/80 transition-colors"
      >
        All Jobs
      </.link>
      <%= if @sidebar_project do %>
        <.link
          navigate={"/projects/#{@sidebar_project.id}/jobs"}
          class="text-xs text-base-content/50 hover:text-base-content/80 transition-colors"
        >
          Project Jobs
        </.link>
      <% end %>
    </div>

    <%= for job <- @jobs do %>
      <.link
        navigate="/jobs"
        data-vim-flyout-item
        class="flex items-center gap-2 px-3 py-2 text-xs text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50 [&.vim-nav-focused]:rounded"
      >
        <span class={[
          "w-1.5 h-1.5 rounded-full flex-shrink-0",
          if(job.enabled, do: "bg-green-500", else: "bg-base-content/20")
        ]} />
        <span class="truncate font-medium flex-1">{job.name}</span>
        <span class="text-micro text-base-content/30 flex-shrink-0 font-mono">
          {job.schedule_value}
        </span>
      </.link>
    <% end %>

    <%= if @jobs == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No jobs</div>
    <% end %>
    """
  end
end
