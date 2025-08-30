defmodule MkapsWeb.MkapsLive do
  use MkapsWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, allow_upload(socket, :any_file, accept: :any, max_file_size: 1_000_000_000)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save", _params, socket) do
    consume_uploaded_entries(socket, :any_file, fn %{path: path}, entry ->
      uploads_path = Application.fetch_env!(:mkaps, MkapsWeb.MkapsLive)[:uploads_path]
      dest = Path.join(uploads_path, "file" <> Path.extname(entry.client_name))
      File.cp!(path, dest)
      {:ok, nil}
    end)
    {:noreply, socket}
  end
end
