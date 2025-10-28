defmodule Mkaps.Repo.Migrations.AddGamePosition do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :position, :integer
    end
  end
end
