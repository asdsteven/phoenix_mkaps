defmodule Mkaps.Repo.Migrations.RenameItemXyzs do
  use Ecto.Migration

  def change do
    rename table(:slides), :sentence_positions, to: :item_xyzs
  end
end
