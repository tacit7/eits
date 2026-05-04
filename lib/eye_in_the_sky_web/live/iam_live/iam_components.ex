defmodule EyeInTheSkyWeb.IAMLive.IAMComponents do
  @moduledoc """
  Shared UI components for IAM LiveViews.
  """
  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents, only: [icon: 1]

  @doc """
  Persistent red banner shown when the IAM hook endpoint is not reachable or
  hooks are not installed in the local Claude Code settings.

  Only rendered in Tauri desktop mode (:installed or :not_installed).
  Hidden in web mode (:not_applicable).
  """
  attr :hooks_status, :atom, required: true

  def iam_offline_banner(assigns) do
    ~H"""
    <%= if @hooks_status == :not_installed do %>
      <div class="flex items-center gap-3 rounded-lg border border-error/40 bg-error/10 px-4 py-3 text-sm text-error">
        <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
        <div class="flex-1">
          <span class="font-semibold">IAM OFFLINE</span>
          <span class="ml-2 text-error/80">
            No policy enforcement active — all tool calls allowed. Install the IAM hook in
            <code class="font-mono text-xs">~/.claude/settings.json</code>
            to enable enforcement.
          </span>
        </div>
      </div>
    <% end %>
    """
  end
end
