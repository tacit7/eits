defmodule EyeInTheSky.Github.PushHandler do
  @moduledoc false
  require Logger

  def handle(ctx) do
    Logger.debug(
      "PushHandler: push event on #{ctx.repository_full_name} branch=#{ctx.head_branch}"
    )

    :ok
  end
end
