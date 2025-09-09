defmodule Mkaps.Repo.Migrations.AddAvatars do
  use Ecto.Migration

  def change do
    alter table(:slides) do
      add :avatars, :map
    end
  end
end
