defmodule EyeInTheSkyWeb.Api.V1.SettingsController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  alias EyeInTheSky.Settings

  def eits_workflow_enabled(conn, _params) do
    json(conn, %{enabled: Settings.get_boolean("eits_workflow_enabled")})
  end
end
