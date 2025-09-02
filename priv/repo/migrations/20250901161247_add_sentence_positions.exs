defmodule Mkaps.Repo.Migrations.AddSentencePositions do
  use Ecto.Migration

  def change do
    alter table(:slides) do
      add :sentence_positions, :map
    end
  end
end
