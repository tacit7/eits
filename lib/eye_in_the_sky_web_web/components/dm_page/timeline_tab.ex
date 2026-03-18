defmodule EyeInTheSkyWebWeb.Components.DmPage.TimelineTab do
  @moduledoc false

  use EyeInTheSkyWebWeb, :html

  attr :checkpoints, :list, default: []
  attr :show_create_checkpoint, :boolean, default: false

  def timeline_tab(assigns) do
    ~H"""
    <div class="space-y-3 p-4 max-w-2xl" id="dm-timeline">
      <%!-- Header row with create button --%>
      <div class="flex items-center justify-between mb-1">
        <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/40">
          Checkpoints
        </h3>
        <button
          type="button"
          phx-click="toggle_create_checkpoint"
          class="btn btn-xs btn-primary gap-1"
        >
          <.icon name="hero-plus-mini" class="w-3 h-3" /> New
        </button>
      </div>

      <%!-- Create checkpoint form --%>
      <%= if @show_create_checkpoint do %>
        <form
          phx-submit="create_checkpoint"
          class="bg-base-100 rounded-xl border border-base-content/8 p-4 space-y-3"
          id="create-checkpoint-form"
        >
          <div class="space-y-1">
            <label class="text-xs font-medium text-base-content/50">Name</label>
            <input
              type="text"
              name="name"
              placeholder="Checkpoint name (optional)"
              class="input input-sm w-full bg-base-200/50 border-base-content/10 text-sm"
              autocomplete="off"
            />
          </div>
          <div class="space-y-1">
            <label class="text-xs font-medium text-base-content/50">Description</label>
            <input
              type="text"
              name="description"
              placeholder="Brief description (optional)"
              class="input input-sm w-full bg-base-200/50 border-base-content/10 text-sm"
              autocomplete="off"
            />
          </div>
          <div class="flex gap-2 justify-end">
            <button type="button" phx-click="toggle_create_checkpoint" class="btn btn-xs btn-ghost">
              Cancel
            </button>
            <button type="submit" class="btn btn-xs btn-primary">Save Checkpoint</button>
          </div>
        </form>
      <% end %>

      <%!-- Empty state --%>
      <%= if @checkpoints == [] do %>
        <.empty_state
          id="dm-timeline-empty"
          icon="hero-clock"
          title="No checkpoints yet"
          subtitle="Save a checkpoint to snapshot this session's state"
        />
      <% else %>
        <%!-- Timeline list --%>
        <div class="relative">
          <%!-- Vertical line --%>
          <div class="absolute left-[11px] top-2 bottom-2 w-px bg-base-content/10" />

          <div class="space-y-3">
            <%= for checkpoint <- @checkpoints do %>
              <div
                class="flex gap-3 group"
                id={"checkpoint-#{checkpoint.id}"}
              >
                <%!-- Dot --%>
                <div class="flex-shrink-0 w-[23px] flex items-start justify-center pt-1">
                  <div class="w-3 h-3 rounded-full bg-primary/60 border-2 border-primary/30 group-hover:bg-primary transition-colors" />
                </div>

                <%!-- Content card --%>
                <div class="flex-1 min-w-0 pb-1">
                  <div class="bg-base-100 rounded-lg border border-base-content/6 px-3 py-2.5 hover:border-base-content/12 transition-colors">
                    <%!-- Name + index badge --%>
                    <div class="flex items-center gap-2 min-w-0">
                      <span class="text-[13px] font-semibold text-base-content/80 truncate flex-1">
                        {checkpoint.name || "Checkpoint at msg #{checkpoint.message_index}"}
                      </span>
                      <span class="text-[10px] font-mono bg-base-200 text-base-content/40 px-1.5 py-0.5 rounded flex-shrink-0">
                        msg #{checkpoint.message_index}
                      </span>
                    </div>

                    <%!-- Description --%>
                    <%= if checkpoint.description do %>
                      <p class="text-[12px] text-base-content/50 mt-0.5 truncate">
                        {checkpoint.description}
                      </p>
                    <% end %>

                    <%!-- Meta row --%>
                    <div class="flex items-center gap-3 mt-1.5 text-[11px] text-base-content/30">
                      <span class="font-mono">
                        {format_checkpoint_time(checkpoint.inserted_at)}
                      </span>
                      <%= if checkpoint.git_stash_ref do %>
                        <span class="inline-flex items-center gap-0.5 text-success/60">
                          <.icon name="hero-code-bracket-mini" class="w-3 h-3" /> git stash
                        </span>
                      <% end %>
                    </div>

                    <%!-- Action buttons --%>
                    <div class="flex gap-1.5 mt-2">
                      <button
                        type="button"
                        phx-click="restore_checkpoint"
                        phx-value-id={checkpoint.id}
                        class="btn btn-xs btn-ghost gap-1 text-warning/70 hover:text-warning hover:bg-warning/10"
                        data-confirm={"Restore to checkpoint '#{checkpoint.name || "msg #{checkpoint.message_index}"}'? Messages after this point will be deleted."}
                      >
                        <.icon name="hero-arrow-uturn-left-mini" class="w-3 h-3" /> Restore
                      </button>
                      <button
                        type="button"
                        phx-click="fork_checkpoint"
                        phx-value-id={checkpoint.id}
                        class="btn btn-xs btn-ghost gap-1 text-primary/70 hover:text-primary hover:bg-primary/10"
                      >
                        <.icon name="hero-arrow-top-right-on-square-mini" class="w-3 h-3" /> Fork
                      </button>
                      <button
                        type="button"
                        phx-click="delete_checkpoint"
                        phx-value-id={checkpoint.id}
                        class="btn btn-xs btn-ghost gap-1 text-error/50 hover:text-error hover:bg-error/10 ml-auto"
                        data-confirm="Delete this checkpoint?"
                      >
                        <.icon name="hero-trash-mini" class="w-3 h-3" />
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_checkpoint_time(nil), do: "—"

  defp format_checkpoint_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %-d, %H:%M")
  rescue
    _ -> "—"
  end

  defp format_checkpoint_time(_), do: "—"
end
