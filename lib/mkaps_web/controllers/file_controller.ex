defmodule MkapsWeb.FileController do
  use MkapsWeb, :controller

  def file(conn, _params) do
    uploads_path = Application.fetch_env!(:mkaps, MkapsWeb.MkapsLive)[:uploads_path]
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("application/pdf")
    |> send_file(200, Path.join(uploads_path, "file.pdf"))
  end
end
