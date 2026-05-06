defmodule EyeInTheSkyWeb.OverviewLive.Agents.AgentDef do
  defstruct [
    :id,
    :slug,
    :filename,
    :path,
    :abs_path,
    :source,
    :name,
    :description,
    :model,
    :tools,
    :content,
    :size,
    :mtime
  ]
end
