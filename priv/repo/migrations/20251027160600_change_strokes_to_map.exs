defmodule Mkaps.Repo.Migrations.ChangeStrokesToMap do
  use Ecto.Migration

  def change do
    alter table(:pads) do
      remove :strokes
      add :strokes, :map
    end
  end
end
