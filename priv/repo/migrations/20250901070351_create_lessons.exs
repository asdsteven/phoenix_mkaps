defmodule Mkaps.Repo.Migrations.CreateLessons do
  use Ecto.Migration

  def change do
    create table(:lessons) do
      add :name, :string

      timestamps(type: :utc_datetime)
    end
  end
end
