defmodule Mkaps.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games) do
      add :name, :string
      add :data, :map

      timestamps(type: :utc_datetime)
    end
  end
end
