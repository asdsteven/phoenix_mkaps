defmodule Mkaps.Repo.Migrations.CreateSlides do
  use Ecto.Migration

  def change do
    create table(:slides) do
      add :position, :integer
      add :sentences, :text
      add :images, :text
      add :lesson_id, references(:lessons, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:slides, [:lesson_id])
  end
end
