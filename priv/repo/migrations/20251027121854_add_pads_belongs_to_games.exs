defmodule Mkaps.Repo.Migrations.AddPadsBelongsToGames do
  use Ecto.Migration

  def change do
    alter table(:pads) do
      add :game_id, references(:games)
    end
  end
end
