defmodule Mkaps.Repo.Migrations.CreatePads do
  use Ecto.Migration

  def change do
    create table(:pads) do
      add :name, :string
      add :strokes, :string

      timestamps(type: :utc_datetime)
    end
  end
end
