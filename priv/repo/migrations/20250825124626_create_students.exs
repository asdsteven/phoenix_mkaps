defmodule Mkaps.Repo.Migrations.CreateStudents do
  use Ecto.Migration

  def change do
    create table(:students) do
      add :name, :string
      add :class_name, :string
      add :class_number, :string

      timestamps(type: :utc_datetime)
    end
  end
end
