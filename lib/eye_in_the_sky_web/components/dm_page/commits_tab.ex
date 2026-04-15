defmodule EyeInTheSkyWeb.Components.DmPage.CommitsTab do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  import EyeInTheSkyWeb.Components.DmHelpers, only: [extract_commit_title: 1, to_utc_string: 1]

  attr :commits, :list, default: []
  attr :diff_cache, :map, default: %{}

  def commits_tab(assigns) do
    ~H"""
    <%= if @commits == [] do %>
      <.empty_state
        id="dm-commits-empty"
        icon="hero-code-bracket"
        title="No commits yet"
        subtitle="Commits from this session will appear here"
      />
    <% else %>
      <div
        class="space-y-1 bg-base-200 rounded-xl shadow-sm p-4"
        id="dm-commit-list"
      >
        <%= for commit <- @commits do %>
          <% hash = commit.commit_hash || "" %>
          <% diff = Map.get(@diff_cache, hash) %>
          <div
            class="collapse collapse-arrow rounded-lg border border-base-content/5 bg-base-200 hover:border-base-content/10 transition-colors"
            id={"dm-commit-#{commit.id}"}
            phx-hook="DiffCollapse"
            data-hash={hash}
            data-loaded={
              cond do
                is_nil(diff) -> "false"
                diff == :error -> "error"
                true -> "true"
              end
            }
          >
            <input type="checkbox" />
            <div class="collapse-title py-3 px-4">
              <div class="flex items-center gap-3">
                <.icon name="hero-code-bracket" class="h-4 w-4 flex-shrink-0 text-base-content/30" />
                <div class="flex-1 min-w-0">
                  <h3 class="text-[13px] font-semibold text-base-content/85 truncate">
                    {extract_commit_title(commit.commit_message)}
                  </h3>
                  <div class="flex items-center gap-1.5 mt-0.5 text-[11px] text-base-content/30">
                    <span class="font-mono">{String.slice(hash, 0..7)}</span>
                    <span class="text-base-content/15">/</span>
                    <time
                      id={"commit-time-#{commit.id}"}
                      class="tabular-nums"
                      data-utc={to_utc_string(commit.created_at)}
                      data-fmt="short"
                      phx-hook="LocalTime"
                    >
                    </time>
                    <span
                      class="loading loading-spinner loading-xs hidden"
                      data-role="diff-spinner"
                    >
                    </span>
                  </div>
                </div>
              </div>
            </div>
            <div class="collapse-content pb-2 overflow-x-auto">
              <%= cond do %>
                <% is_nil(diff) -> %>
                  <div></div>
                <% diff == :error -> %>
                  <div class="px-4 py-2 text-xs text-error/60">
                    Could not load diff — repo path unavailable
                  </div>
                <% true -> %>
                  <div
                    id={"diff-#{commit.id}"}
                    phx-hook="DiffViewer"
                    data-diff={diff}
                  />
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end
end
