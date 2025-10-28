defmodule Mkaps.Repo.Migrations.AddGamesLayout do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :layout, :string
    end
  end
end
