defmodule Mkaps.Repo do
  use Ecto.Repo,
    otp_app: :mkaps,
    adapter: Ecto.Adapters.SQLite3
end
