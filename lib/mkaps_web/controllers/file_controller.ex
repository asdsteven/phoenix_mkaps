defmodule MkapsWeb.FileController do
  use MkapsWeb, :controller

  def file(conn, _params) do
    uploads_path = Application.fetch_env!(:mkaps, MkapsWeb.FileLive)[:uploads_path]
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("application/pdf")
    |> send_file(200, Path.join(uploads_path, "file.pdf"))
  end

  def image(conn, %{"filename" => filename}) do
    uploads_path = Application.fetch_env!(:mkaps, MkapsWeb.FileLive)[:uploads_path]
    path = Path.join(uploads_path, Path.basename(filename))
    conn
    |> put_resp_content_type(MIME.from_path(path))
    |> send_file(200, path)
  end
end
