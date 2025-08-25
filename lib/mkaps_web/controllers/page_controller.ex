defmodule MkapsWeb.PageController do
  use MkapsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
