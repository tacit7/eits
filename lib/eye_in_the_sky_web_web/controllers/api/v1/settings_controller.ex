defmodule EyeInTheSkyWebWeb.Api.V1.SettingsController do
  use EyeInTheSkyWebWeb, :controller

  action_fallback EyeInTheSkyWebWeb.Api.V1.FallbackController

  alias EyeInTheSkyWeb.Settings

  def eits_workflow_enabled(conn, _params) do
    json(conn, %{enabled: Settings.get_boolean("eits_workflow_enabled")})
  end
end
