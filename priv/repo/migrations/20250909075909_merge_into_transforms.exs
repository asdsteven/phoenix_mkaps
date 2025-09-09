defmodule Mkaps.Repo.Migrations.MergeIntoTransforms do
  use Ecto.Migration

  def change do
    alter table(:slides) do
      add :transforms, :map
      remove :font_size
      remove :image_size
      remove :item_xyzs
      remove :item_sizes
    end
  end
end
