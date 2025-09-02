defmodule Mkaps.Repo.Migrations.AddLessonPosition do
  use Ecto.Migration

  def change do
    alter table(:lessons) do
      add :position, :integer
    end
  end
end
