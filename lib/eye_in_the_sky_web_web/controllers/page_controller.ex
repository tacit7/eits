defmodule EyeInTheSkyWebWeb.PageController do
  use EyeInTheSkyWebWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
