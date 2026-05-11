defmodule EyeInTheSky.Github.CheckRunHandler do
  require Logger

  def handle(ctx) do
    Logger.debug(
      "CheckRunHandler: #{ctx.event_type} on #{ctx.repository_full_name} branch=#{ctx.head_branch}"
    )

    :ok
  end
end
