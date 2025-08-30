defmodule MkapsWeb.FileController do
  use MkapsWeb, :controller

  def file(conn, _params) do
    uploads_path = Application.fetch_env!(:mkaps, MkapsWeb.MkapsLive)[:uploads_path]
    send_file(conn, 200, Path.join(uploads_path, "file.pdf"))
  end
end
