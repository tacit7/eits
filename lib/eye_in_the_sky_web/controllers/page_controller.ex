defmodule EyeInTheSkyWeb.PageController do
  use EyeInTheSkyWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
