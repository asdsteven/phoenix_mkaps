defmodule Mkaps.Repo.Migrations.AddFontImageSize do
  use Ecto.Migration

  def change do
    alter table(:slides) do
      add :font_size, :integer
      add :image_size, :integer
      add :item_sizes, :map
    end
  end
end
